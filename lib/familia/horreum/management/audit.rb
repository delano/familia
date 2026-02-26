# lib/familia/horreum/management/audit.rb
#
# frozen_string_literal: true

module Familia
  class Horreum
    # AuditMethods provides proactive consistency detection for Horreum models.
    #
    # Included in ManagementMethods so every Horreum subclass gets these as
    # class methods (e.g. Customer.audit_instances, Customer.health_check).
    #
    module AuditMethods
      # Compares the instances timeline against actual DB keys via SCAN.
      #
      # Detects:
      # - Phantoms: identifiers in timeline but no corresponding hash key
      # - Missing: hash keys in DB but not in timeline
      #
      # @param batch_size [Integer] SCAN cursor count hint (default: 100)
      # @yield [Hash] Progress: {phase:, current:, total:}
      # @return [Hash] {phantoms: [], missing: [], count_timeline: N, count_scan: N}
      #
      def audit_instances(batch_size: 100, &progress)
        # Phase 1: Collect identifiers from timeline
        timeline_ids = Set.new(instances.members)
        progress&.call(phase: :timeline_collected, current: timeline_ids.size, total: nil)

        # Phase 2: SCAN keys and extract identifiers (source of truth)
        scan_ids = scan_identifiers(batch_size: batch_size, &progress)

        # Phase 3: Set differences
        phantoms = (timeline_ids - scan_ids).to_a
        missing = (scan_ids - timeline_ids).to_a

        {
          phantoms: phantoms,
          missing: missing,
          count_timeline: timeline_ids.size,
          count_scan: scan_ids.size,
        }
      end

      # Audits all unique indexes (class-level only, where within is nil).
      #
      # For each unique index:
      # - Reads all entries from the index HashKey
      # - Checks that each indexed object exists and its field value matches
      # - Checks for objects that should be indexed but aren't
      #
      # @return [Array<Hash>] [{index_name:, stale: [...], missing: [...]}]
      #
      def audit_unique_indexes
        return [] unless respond_to?(:indexing_relationships)

        indexing_relationships.select { |r|
          r.cardinality == :unique && r.within.nil?
        }.map { |rel| audit_single_unique_index(rel) }
      end

      # Audits all multi indexes.
      #
      # For each multi index:
      # - SCANs for per-value set keys
      # - Checks that each member exists and field value matches
      # - Detects orphaned set keys (sets for values no object has)
      #
      # @return [Array<Hash>] [{index_name:, stale_members: [], orphaned_keys: []}]
      #
      def audit_multi_indexes
        return [] unless respond_to?(:indexing_relationships)

        indexing_relationships.select { |r|
          r.cardinality == :multi
        }.map { |rel| audit_single_multi_index(rel) }
      end

      # Audits participation collections for stale members.
      #
      # For each participation relationship defined on this class:
      # - Class-level: checks the single class collection directly
      # - Instance-level: SCANs for collection keys on the target class
      # - Enumerates raw members of each collection
      # - Verifies each referenced participant object still exists
      #
      # @param sample_size [Integer, nil] Limit members to check per collection (nil = all)
      # @return [Array<Hash>] [{collection_name:, stale_members: [{identifier:, collection_key:, reason:}]}]
      #
      def audit_participations(sample_size: nil)
        return [] unless respond_to?(:participation_relationships)

        participation_relationships.flat_map { |rel|
          if rel.target_class == self
            # Class-level participation (class_participates_in)
            [audit_class_participation(rel, sample_size: sample_size)]
          else
            # Instance-level participation (participates_in TargetClass, :collection)
            audit_instance_participations(rel, sample_size: sample_size)
          end
        }
      end

      # Runs all four audits and wraps results in an AuditReport.
      #
      # @param batch_size [Integer] SCAN batch size for instances audit
      # @param sample_size [Integer, nil] Sample size for participation audit
      # @yield [Hash] Progress from audit_instances
      # @return [AuditReport]
      #
      def health_check(batch_size: 100, sample_size: nil, &progress)
        start_time = Familia.now

        inst = audit_instances(batch_size: batch_size, &progress)
        uniq = audit_unique_indexes
        multi = audit_multi_indexes
        parts = audit_participations(sample_size: sample_size)

        duration = Familia.now - start_time

        AuditReport.new(
          model_class: name,
          audited_at: start_time,
          instances: inst,
          unique_indexes: uniq,
          multi_indexes: multi,
          participations: parts,
          duration: duration
        )
      end

      private

      # SCANs DB hash keys and extracts identifiers.
      #
      # This is the source of truth for what objects actually exist — it
      # bypasses the instances timeline entirely.
      #
      # @param batch_size [Integer] SCAN cursor count hint (default: 100)
      # @yield [Hash] Optional progress callback
      # @return [Set<String>] Identifiers extracted from scanned keys
      #
      def scan_identifiers(batch_size: 100, &progress)
        ids = Set.new
        pattern = scan_pattern
        cursor = "0"

        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: batch_size)
          keys.each do |key|
            parts = Familia.split(key)
            next unless parts.length >= 2

            ids << parts[1]
          end
          progress&.call(phase: :scanning, current: ids.size, total: nil)
          break if cursor == "0"
        end

        ids
      end

      # Audit a single unique index (class-level).
      #
      # @param rel [IndexingRelationship]
      # @return [Hash] {index_name:, stale: [], missing: []}
      #
      def audit_single_unique_index(rel)
        index_name = rel.index_name
        field = rel.field
        stale = []
        missing = []

        # The class-level index accessor
        return { index_name: index_name, stale: stale, missing: missing } unless respond_to?(index_name)

        index_hashkey = send(index_name)
        entries = index_hashkey.hgetall # {field_value => deserialized_value}

        # Extract identifiers from all index entries for batch loading.
        # hgetall on HashKey already deserializes values, so we work with
        # Ruby objects here (strings or Horreum instances depending on storage).
        entry_identifiers = entries.map do |_field_value, deserialized_id|
          id = deserialized_id
          id = id.identifier if id.respond_to?(:identifier)
          id.to_s
        end

        # Batch-load all indexed objects in a single pipelined HGETALL round-trip
        # instead of N individual exists? + find_by_id calls.
        entry_objects = load_multi(entry_identifiers)

        entries.each_with_index do |(field_value, _deserialized_id), idx|
          identifier = entry_identifiers[idx]
          obj = entry_objects[idx]

          unless obj
            stale << { field_value: field_value, indexed_id: identifier, reason: :object_missing }
            next
          end

          # Verify field value still matches
          current_value = obj.send(field).to_s
          unless current_value == field_value
            stale << { field_value: field_value, indexed_id: identifier, reason: :value_mismatch,
                       current_value: current_value }
          end
        end

        # Check for objects that should be indexed but aren't.
        # SCAN for all hash keys (source of truth) instead of relying on
        # the instances timeline, which may contain ghosts or miss entries.
        indexed_values = entries.keys.to_set
        all_identifiers = scan_identifiers.to_a
        all_objects = load_multi(all_identifiers)

        all_identifiers.each_with_index do |identifier, idx|
          obj = all_objects[idx]
          next unless obj

          value = obj.send(field)
          next if value.nil? || value.to_s.strip.empty?

          unless indexed_values.include?(value.to_s)
            missing << { identifier: identifier, field_value: value.to_s }
          end
        end

        { index_name: index_name, stale: stale, missing: missing }
      end

      # Audit a single multi index.
      #
      # @param rel [IndexingRelationship]
      # @return [Hash] {index_name:, stale_members: [], orphaned_keys: []}
      #
      def audit_single_multi_index(rel)
        index_name = rel.index_name
        field = rel.field
        stale_members = []
        orphaned_keys = []

        # Multi-indexes require a scope, use within to determine the scope class
        scope_class = rel.within
        if scope_class.nil? || scope_class == :class
          return { index_name: index_name, stale_members: stale_members, orphaned_keys: orphaned_keys }
        end

        # Multi-index audit requires enumerating all scope instances to discover
        # per-value set keys, which is expensive. Return empty results with a
        # status flag so callers know this dimension was not actually checked.
        Familia.debug "[audit_multi_indexes] #{name}##{index_name}: not_implemented (requires scope instance enumeration)"
        { index_name: index_name, stale_members: stale_members, orphaned_keys: orphaned_keys, status: :not_implemented }
      end

      # Audit a class-level participation collection (from class_participates_in).
      #
      # The collection lives on this class directly (e.g., Domain.all_domains).
      # Enumerates raw members and checks if each participant object still
      # exists in the database.
      #
      # @param rel [ParticipationRelationship]
      # @param sample_size [Integer, nil]
      # @return [Hash] {collection_name:, stale_members: [{identifier:, collection_key:, reason:}]}
      #
      def audit_class_participation(rel, sample_size: nil)
        collection_name = rel.collection_name
        stale = []

        return { collection_name: collection_name, stale_members: stale } unless respond_to?(collection_name)

        collection = send(collection_name)
        collection_key = collection.dbkey

        # Raw members are the serialized form stored in Redis. For Familia
        # objects added to collections, this is the raw identifier string.
        raw_members = collection.membersraw
        raw_members = raw_members.sample(sample_size) if sample_size

        raw_members.each do |raw_member|
          unless exists?(raw_member)
            stale << {
              identifier: raw_member,
              collection_key: collection_key,
              collection_name: collection_name,
              reason: :object_missing,
            }
          end
        end

        { collection_name: collection_name, stale_members: stale }
      end

      # Audit instance-level participation collections (from participates_in).
      #
      # The collections live on individual target instances (e.g.,
      # customer.domains for each Customer). SCANs Redis for all
      # collection keys matching the target pattern and checks each
      # collection's members for stale participant identifiers.
      #
      # @param rel [ParticipationRelationship]
      # @param sample_size [Integer, nil]
      # @return [Array<Hash>] One result per collection key found:
      #   [{collection_name:, stale_members: [{identifier:, collection_key:, reason:}]}]
      #
      def audit_instance_participations(rel, sample_size: nil)
        collection_name = rel.collection_name
        target_class = rel.target_class
        results = []

        # SCAN for all collection keys matching target_prefix:*:collection_name
        pattern = "#{target_class.prefix}:*:#{collection_name}"
        collection_keys = scan_matching_keys(pattern, target_class.dbclient)

        collection_keys.each do |collection_key|
          stale = audit_collection_key_members(
            collection_key, rel, sample_size: sample_size
          )
          results << { collection_name: collection_name, stale_members: stale }
        end

        # Return at least one entry even when no collection keys exist,
        # so the report structure is always consistent.
        results << { collection_name: collection_name, stale_members: [] } if results.empty?
        results
      end

      # Check a single collection key for stale members.
      #
      # Uses raw Redis commands (SMEMBERS, ZRANGE, LRANGE) appropriate to
      # the collection type, then verifies each member against EXISTS on
      # the participant class (self).
      #
      # @param collection_key [String] Full Redis key (e.g. "customer:cust1:domains")
      # @param rel [ParticipationRelationship]
      # @param sample_size [Integer, nil]
      # @return [Array<Hash>] Stale member entries
      #
      def audit_collection_key_members(collection_key, rel, sample_size: nil)
        stale = []
        client = rel.target_class.dbclient

        raw_members = case rel.type
                      when :sorted_set
                        client.zrange(collection_key, 0, -1)
                      when :set
                        client.smembers(collection_key)
                      when :list
                        client.lrange(collection_key, 0, -1)
                      else
                        return stale
                      end

        raw_members = raw_members.sample(sample_size) if sample_size

        raw_members.each do |raw_member|
          unless exists?(raw_member)
            stale << {
              identifier: raw_member,
              collection_key: collection_key,
              collection_name: rel.collection_name,
              reason: :object_missing,
            }
          end
        end

        stale
      end

      # SCAN helper for finding keys matching a pattern.
      #
      # @param pattern [String] Redis key pattern (e.g. "customer:*:domains")
      # @param client [Redis] Redis client to use
      # @param batch_size [Integer] SCAN cursor count hint
      # @return [Array<String>] Matching keys
      #
      def scan_matching_keys(pattern, client, batch_size: 100)
        keys = []
        cursor = "0"

        loop do
          cursor, batch = client.scan(cursor, match: pattern, count: batch_size)
          keys.concat(batch)
          break if cursor == "0"
        end

        keys
      end
    end
  end
end
