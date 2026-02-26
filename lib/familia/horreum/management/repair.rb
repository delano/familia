# lib/familia/horreum/management/repair.rb
#
# frozen_string_literal: true

module Familia
  class Horreum
    # RepairMethods provides repair and rebuild operations for Horreum models.
    #
    # Included in ManagementMethods so every Horreum subclass gets these as
    # class methods (e.g. Customer.repair_instances!, Customer.rebuild_instances).
    #
    module RepairMethods
      # Repairs the instances timeline by removing phantoms and adding missing entries.
      #
      # @param audit_result [Hash, nil] Result from audit_instances (runs audit if nil)
      # @return [Hash] {phantoms_removed: N, missing_added: N}
      #
      def repair_instances!(audit_result = nil)
        audit_result ||= audit_instances

        phantoms_removed = 0
        missing_added = 0

        # Remove phantoms (in timeline but key expired/deleted).
        # Batch all ZREMs in a single pipeline to avoid N round-trips.
        phantoms = audit_result[:phantoms]
        unless phantoms.empty?
          instances_key = instances.dbkey
          pipelined do |pipe|
            phantoms.each do |identifier|
              pipe.zrem(instances_key, identifier)
            end
          end
          phantoms_removed = phantoms.size
        end

        # Add missing (key exists but not in timeline).
        # Batch-load all objects via load_multi, then batch ZADDs in a pipeline.
        missing = audit_result[:missing]
        unless missing.empty?
          objects = load_multi(missing)
          instances_key = instances.dbkey
          pipelined do |pipe|
            missing.each_with_index do |identifier, idx|
              obj = objects[idx]
              score = extract_timestamp_score(obj)
              pipe.zadd(instances_key, score, identifier)
            end
          end
          missing_added = missing.size
        end

        { phantoms_removed: phantoms_removed, missing_added: missing_added }
      end

      # Full SCAN-based rebuild of the instances timeline with atomic swap.
      #
      # Scans all hash keys matching this class's pattern, extracts identifiers,
      # and rebuilds the sorted set with timestamps from the objects.
      #
      # @param batch_size [Integer] SCAN cursor count hint (default: 100)
      # @yield [Hash] Progress: {phase:, current:, total:}
      # @return [Integer] Number of instances rebuilt
      #
      def rebuild_instances(batch_size: 100, &progress)
        pattern = scan_pattern
        final_key = instances.dbkey
        temp_key = "#{final_key}:rebuild:#{Familia.now.to_i}"

        count = 0
        cursor = "0"
        batch = []

        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: batch_size)

          keys.each do |key|
            parts = Familia.split(key)
            next unless parts.length >= 2

            batch << { key: key, identifier: parts[1] }
          end

          # Process batch when it reaches threshold
          if batch.size >= batch_size
            count += process_rebuild_batch(batch, temp_key)
            progress&.call(phase: :rebuilding, current: count, total: nil)
            batch.clear
          end

          break if cursor == "0"
        end

        # Process remaining batch
        unless batch.empty?
          count += process_rebuild_batch(batch, temp_key)
          progress&.call(phase: :rebuilding, current: count, total: nil)
        end

        # Atomic swap
        Familia::Features::Relationships::Indexing::RebuildStrategies.atomic_swap(
          temp_key, final_key, dbclient
        )

        progress&.call(phase: :completed, current: count, total: count)
        count
      end

      # Repairs indexes by running existing rebuild methods for stale indexes.
      #
      # @param audit_results [Array<Hash>, nil] Results from audit_unique_indexes
      # @return [Hash] {rebuilt: [index_names]}
      #
      def repair_indexes!(audit_results = nil)
        audit_results ||= audit_unique_indexes

        rebuilt = []

        audit_results.each do |idx_result|
          index_name = idx_result[:index_name]
          next if idx_result[:stale].empty? && idx_result[:missing].empty?

          rebuild_method = :"rebuild_#{index_name}"
          if respond_to?(rebuild_method)
            send(rebuild_method)
            rebuilt << index_name
          end
        end

        { rebuilt: rebuilt }
      end

      # Repairs participation collections by removing stale members.
      #
      # Removes identifiers from the actual participation collections
      # (not the instances timeline). Each stale entry from the audit
      # carries a collection_key identifying the exact Redis key to
      # remove from, plus the raw identifier string to remove.
      #
      # Uses raw Redis commands (ZREM/SREM/LREM) because the stored
      # member values are raw identifier strings (not JSON-encoded),
      # and the DataType#remove method would JSON-encode string args.
      #
      # @param audit_results [Array<Hash>, nil] Results from audit_participations
      # @return [Hash] {stale_removed: N}
      #
      def repair_participations!(audit_results = nil)
        audit_results ||= audit_participations

        stale_removed = 0

        audit_results.each do |part_result|
          part_result[:stale_members].each do |entry|
            identifier = entry[:identifier]
            collection_key = entry[:collection_key]
            next unless collection_key && identifier

            removed = remove_stale_collection_member(collection_key, identifier)
            stale_removed += 1 if removed
          end
        end

        { stale_removed: stale_removed }
      end

      # Runs health_check then all repair methods.
      #
      # @param batch_size [Integer] SCAN batch size
      # @yield [Hash] Progress callbacks
      # @return [Hash] Combined repair results plus the AuditReport
      #
      def repair_all!(batch_size: 100, &progress)
        report = health_check(batch_size: batch_size, &progress)

        instances_result = repair_instances!(report.instances)
        indexes_result = repair_indexes!(report.unique_indexes)
        participations_result = repair_participations!(report.participations)

        {
          report: report,
          instances: instances_result,
          indexes: indexes_result,
          participations: participations_result,
        }
      end

      # SCAN helper for enumerating keys matching a pattern.
      #
      # @param filter [String] Glob filter appended to class prefix (default: '*')
      # @param batch_size [Integer] SCAN cursor count hint (default: 100)
      # @yield [String] Each matching key
      # @return [Enumerator] If no block given
      #
      def scan_keys(filter = '*', batch_size: 100, &block)
        pattern = dbkey(filter)
        return enum_for(:scan_keys, filter, batch_size: batch_size) unless block_given?

        cursor = "0"
        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: batch_size)
          keys.each(&block)
          break if cursor == "0"
        end
      end

      private

      # Process a batch of key/identifier pairs for rebuild_instances.
      #
      # @param batch [Array<Hash>] [{key:, identifier:}]
      # @param temp_key [String] Temporary sorted set key
      # @return [Integer] Number of entries added
      #
      def process_rebuild_batch(batch, temp_key)
        identifiers = batch.map { |b| b[:identifier] }
        objects = load_multi(identifiers)

        # Batch all ZADDs in a single pipeline instead of N individual round-trips.
        pipelined do |pipe|
          batch.each_with_index do |entry, idx|
            obj = objects[idx]
            score = extract_timestamp_score(obj)
            pipe.zadd(temp_key, score, entry[:identifier])
          end
        end

        batch.size
      end

      # Extracts a timestamp score from an object for the instances sorted set.
      #
      # Prefers `updated`, then `created`, then falls back to Familia.now.
      #
      # @param obj [Object, nil] A Horreum instance
      # @return [Float] Timestamp score
      #
      def extract_timestamp_score(obj)
        unless obj
          Familia.debug "[extract_timestamp_score] obj is nil, falling back to Familia.now"
          return Familia.now
        end

        if obj.respond_to?(:updated) && obj.updated
          obj.updated.to_f
        elsif obj.respond_to?(:created) && obj.created
          obj.created.to_f
        else
          Familia.debug "[extract_timestamp_score] #{obj.class}##{obj.identifier} has no timestamp fields, falling back to Familia.now"
          Familia.now
        end
      end

      # Removes a stale member from a collection using raw Redis commands.
      #
      # Detects the collection type via TYPE and uses the appropriate
      # removal command (ZREM for sorted sets, SREM for sets, LREM for lists).
      #
      # Raw commands are necessary because DataType#remove calls
      # serialize_value, which JSON-encodes strings. The stored member
      # values are raw identifier strings (serialized from Familia objects),
      # so we must match them exactly.
      #
      # @param collection_key [String] Full Redis key of the collection
      # @param raw_member [String] The raw member value to remove
      # @return [Boolean] true if removal succeeded
      #
      def remove_stale_collection_member(collection_key, raw_member)
        client = dbclient
        key_type = client.type(collection_key)

        case key_type
        when 'zset'
          client.zrem(collection_key, raw_member)
        when 'set'
          client.srem(collection_key, raw_member)
        when 'list'
          # LREM count=0 removes all occurrences
          client.lrem(collection_key, 0, raw_member)
        when 'none'
          # Key no longer exists, nothing to remove
          false
        else
          Familia.debug "[repair_participations!] Unknown key type '#{key_type}' for #{collection_key}"
          false
        end
      end
    end
  end
end
