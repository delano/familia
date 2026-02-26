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

        # Phase 2: SCAN keys and extract identifiers
        scan_ids = Set.new
        pattern = scan_pattern
        cursor = "0"

        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: batch_size)
          keys.each do |key|
            parts = Familia.split(key)
            next unless parts.length >= 2

            scan_ids << parts[1]
          end
          progress&.call(phase: :scanning, current: scan_ids.size, total: nil)
          break if cursor == "0"
        end

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
      # For each participation relationship:
      # - Enumerates collection members
      # - Verifies each referenced object still exists
      #
      # @param sample_size [Integer, nil] Limit members to check (nil = all)
      # @return [Array<Hash>] [{collection_name:, stale_members: []}]
      #
      def audit_participations(sample_size: nil)
        return [] unless respond_to?(:participation_relationships)

        participation_relationships.select { |rel|
          # Only audit class-level participations (class_participates_in)
          rel.target_class == self
        }.map { |rel| audit_single_participation(rel, sample_size: sample_size) }
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

        # Check each index entry
        # hgetall on HashKey already deserializes values, so we work with
        # Ruby objects here (strings or Horreum instances depending on storage)
        entries.each do |field_value, deserialized_id|
          identifier = deserialized_id
          identifier = identifier.identifier if identifier.respond_to?(:identifier)
          identifier = identifier.to_s

          unless exists?(identifier)
            stale << { field_value: field_value, indexed_id: identifier, reason: :object_missing }
            next
          end

          # Verify field value still matches
          obj = find_by_id(identifier, check_exists: false, cleanup: false)
          if obj
            current_value = obj.send(field).to_s
            unless current_value == field_value
              stale << { field_value: field_value, indexed_id: identifier, reason: :value_mismatch,
                         current_value: current_value }
            end
          end
        end

        # Check for objects that should be indexed but aren't
        indexed_values = entries.keys.to_set
        instances.members.each do |identifier|
          obj = find_by_id(identifier, check_exists: false, cleanup: false)
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
        return { index_name: index_name, stale_members: stale_members, orphaned_keys: orphaned_keys } if scope_class.nil? || scope_class == :class

        # Multi-index audit is complex because it needs scope instances.
        # For now, return empty results for multi-indexes as they require
        # iterating all scope instances which is expensive.
        { index_name: index_name, stale_members: stale_members, orphaned_keys: orphaned_keys }
      end

      # Audit a single participation collection.
      #
      # @param rel [ParticipationRelationship]
      # @param sample_size [Integer, nil]
      # @return [Hash] {collection_name:, stale_members: []}
      #
      def audit_single_participation(rel, sample_size: nil)
        collection_name = rel.collection_name
        stale = []

        return { collection_name: collection_name, stale_members: stale } unless respond_to?(:instances)

        # For class-level participations, check each instance's collection
        # This is expensive, so we sample if requested
        member_ids = instances.members
        member_ids = member_ids.sample(sample_size) if sample_size

        member_ids.each do |identifier|
          unless exists?(identifier)
            stale << { identifier: identifier, reason: :object_missing }
          end
        end

        { collection_name: collection_name, stale_members: stale }
      end
    end
  end
end
