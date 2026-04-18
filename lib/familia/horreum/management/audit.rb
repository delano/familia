# lib/familia/horreum/management/audit.rb
#
# frozen_string_literal: true

require 'set'

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

      # Audits instance-level related_fields (list/set/zset/hashkey) for
      # orphaned collection keys whose parent Horreum hash no longer exists.
      #
      # destroy! cleans related fields inside a transaction, so orphans only
      # arise when destroy! is interrupted (process crash, manual Redis
      # tampering, bugs in older code paths). This audit surfaces those cases.
      #
      # Class-level related fields (class_list/class_set/class_hashkey) are
      # intentionally skipped: their keys are {prefix}:{field_name} with no
      # identifier segment, so they cannot be orphaned by instance destruction.
      #
      # @return [Array<Hash>] One entry per instance-level related field:
      #   [{field_name:, klass:, orphaned_keys: [...], count:, status:}]
      #
      def audit_related_fields
        return [] unless relations?

        related_fields.values.map { |definition| audit_single_related_field(definition) }
      end

      # Runs all audits and wraps results in an AuditReport.
      #
      # The related_fields audit is opt-in via `audit_collections: true`
      # because it performs an additional SCAN per instance-level field.
      # When omitted (or false), AuditReport#related_fields is nil which
      # signals "not checked" rather than "checked and clean".
      #
      # @param batch_size [Integer] SCAN batch size for instances audit
      # @param sample_size [Integer, nil] Sample size for participation audit
      # @param audit_collections [Boolean] When true, also run audit_related_fields
      # @yield [Hash] Progress from audit_instances
      # @return [AuditReport]
      #
      def health_check(batch_size: 100, sample_size: nil, audit_collections: false, &progress)
        start_time = Familia.now

        inst = audit_instances(batch_size: batch_size, &progress)
        uniq = audit_unique_indexes
        multi = audit_multi_indexes
        parts = audit_participations(sample_size: sample_size)
        related = audit_collections ? audit_related_fields : nil

        duration = Familia.now - start_time

        AuditReport.new(
          model_class: name,
          audited_at: start_time,
          instances: inst,
          unique_indexes: uniq,
          multi_indexes: multi,
          participations: parts,
          related_fields: related,
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
            identifier = extract_identifier_from_key(key)
            next if identifier.nil? || identifier.empty?

            ids << identifier
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
      # Class-level multi-indexes (within: nil or within: :class) are fully
      # audited. Instance-scoped multi-indexes (within: SomeClass) require
      # enumerating every scope instance to discover per-value set keys; that
      # path is not implemented yet and returns status: :not_implemented.
      #
      # @param rel [IndexingRelationship]
      # @return [Hash] {index_name:, stale_members: [], missing: [], orphaned_keys: [], status:}
      #
      def audit_single_multi_index(rel)
        index_name = rel.index_name

        unless rel.class_level?
          Familia.debug "[audit_multi_indexes] #{name}##{index_name}: " \
                        "instance-scoped audit (within: #{rel.within.inspect}) not implemented; " \
                        'requires enumerating every scope instance to discover per-value set keys'
          return {
            index_name: index_name,
            stale_members: [],
            missing: [],
            orphaned_keys: [],
            status: :not_implemented,
          }
        end

        audit_class_level_multi_index(rel)
      end

      # Audit a class-level multi index.
      #
      # Three-phase audit mirroring the rebuild flow:
      #   1. SCAN for per-value set keys, inspect members for stale references
      #   2. SCAN instance hash keys, detect objects whose field value has no bucket
      #   3. Detect orphaned buckets whose field_value no live object holds
      #
      # Key layout: "{prefix}:{index_name}:{field_value}"
      #
      # @param rel [IndexingRelationship]
      # @return [Hash] {index_name:, stale_members:, missing:, orphaned_keys:, status:}
      #
      def audit_class_level_multi_index(rel)
        bucket_entries = discover_multi_index_buckets(rel)
        discovered_field_values = bucket_entries.keys.to_set

        stale_members = detect_multi_index_stale_members(rel, bucket_entries)
        missing, actual_field_values = detect_multi_index_missing(rel, discovered_field_values)
        orphaned_keys = detect_multi_index_orphaned_keys(bucket_entries, actual_field_values)

        status = if stale_members.empty? && missing.empty? && orphaned_keys.empty?
          :ok
        else
          :issues_found
        end

        {
          index_name: rel.index_name,
          stale_members: stale_members,
          missing: missing,
          orphaned_keys: orphaned_keys,
          status: status,
        }
      end

      # Phase 1: SCAN for per-value set keys and load their raw members.
      #
      # @param rel [IndexingRelationship]
      # @return [Hash{String => Hash}] field_value => {key:, identifiers: [...]}
      #
      def discover_multi_index_buckets(rel)
        bucket_pattern = "#{prefix}:#{rel.index_name}:*"
        bucket_prefix = "#{prefix}:#{rel.index_name}:"
        bucket_entries = {}

        dbclient.scan_each(match: bucket_pattern) do |key|
          next unless key.start_with?(bucket_prefix)

          field_value = key[bucket_prefix.length..]
          next if field_value.nil? || field_value.empty?

          raw_members = dbclient.smembers(key)
          bucket_entries[field_value] = {
            key: key,
            identifiers: deserialize_index_members(raw_members),
          }
        end

        bucket_entries
      end

      # Phase 1 continued: detect stale members (object missing or value mismatch).
      #
      # @param rel [IndexingRelationship]
      # @param bucket_entries [Hash]
      # @return [Array<Hash>]
      #
      def detect_multi_index_stale_members(rel, bucket_entries)
        stale = []

        bucket_entries.each do |field_value, entry|
          identifiers = entry[:identifiers].map(&:to_s)
          next if identifiers.empty?

          objects = load_multi(identifiers)

          identifiers.each_with_index do |identifier, idx|
            stale << classify_multi_index_entry(rel, field_value, identifier, objects[idx])
          end
        end

        stale.compact
      end

      # Classifies a single indexed entry as missing object, value mismatch, or valid.
      #
      # @return [Hash, nil] stale entry or nil when valid
      #
      def classify_multi_index_entry(rel, field_value, identifier, obj)
        if obj.nil?
          return {
            field_value: field_value,
            indexed_id: identifier,
            reason: :object_missing,
          }
        end

        current_value = obj.send(rel.field).to_s
        return nil if current_value == field_value

        {
          field_value: field_value,
          indexed_id: identifier,
          reason: :value_mismatch,
          current_value: current_value,
        }
      end

      # Phase 2: SCAN instance hash keys, detect live objects whose field value
      # has no bucket.
      #
      # @param rel [IndexingRelationship]
      # @param discovered_field_values [Set<String>]
      # @return [Array(Array<Hash>, Set<String>)] missing entries and the set of
      #   field values observed on live objects
      #
      def detect_multi_index_missing(rel, discovered_field_values)
        all_identifiers = scan_identifiers.to_a
        all_objects = load_multi(all_identifiers)
        actual_field_values = Set.new
        missing = []

        all_identifiers.each_with_index do |identifier, idx|
          obj = all_objects[idx]
          next unless obj

          value = obj.send(rel.field)
          next if value.nil? || value.to_s.strip.empty?

          expected_value = value.to_s
          actual_field_values << expected_value

          next if discovered_field_values.include?(expected_value)

          missing << { identifier: identifier, field_value: expected_value }
        end

        [missing, actual_field_values]
      end

      # Phase 3: detect orphaned buckets whose field_value no live object holds.
      #
      # @param bucket_entries [Hash]
      # @param actual_field_values [Set<String>]
      # @return [Array<Hash>]
      #
      def detect_multi_index_orphaned_keys(bucket_entries, actual_field_values)
        orphaned = []

        bucket_entries.each do |field_value, entry|
          next if actual_field_values.include?(field_value)

          orphaned << { field_value: field_value, key: entry[:key] }
        end

        orphaned
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

      # Audits a single instance-level related field for orphaned keys.
      #
      # SCAN pattern "{prefix}:*:{field_name}" discovers all existing
      # collection keys for the field. For each match, extract the
      # identifier and check whether the parent hash still exists.
      # Matches with a missing parent are reported as orphaned.
      #
      # The SCAN pattern does not match class-level keys because those
      # live at "{prefix}:{field_name}" (two segments, no middle wildcard).
      #
      # @param definition [RelatedFieldDefinition]
      # @return [Hash] {field_name:, klass:, orphaned_keys: [], count:, status:}
      #
      def audit_single_related_field(definition)
        field_name = definition.name
        pattern = "#{prefix}#{Familia.delim}*#{Familia.delim}#{field_name}"
        orphaned_keys = []

        dbclient.scan_each(match: pattern) do |key|
          identifier = extract_identifier_from_key(key, field_name.to_s)
          next if identifier.nil? || identifier.empty?

          orphaned_keys << key unless exists?(identifier)
        end

        status = orphaned_keys.empty? ? :ok : :issues_found

        {
          field_name: field_name,
          klass: definition.klass.name,
          orphaned_keys: orphaned_keys,
          count: orphaned_keys.size,
          status: status,
        }
      end

      # Deserializes raw SMEMBERS output from a multi-index bucket.
      #
      # Members are stored via UnsortedSet#add which JSON-encodes values
      # (e.g. "csid-1" -> "\"csid-1\""). Falls back to the raw value when
      # a member cannot be parsed as JSON.
      #
      # @param raw_members [Array<String>] SMEMBERS output
      # @return [Array<Object>] deserialized identifiers
      #
      def deserialize_index_members(raw_members)
        raw_members.filter_map do |raw|
          next if raw.nil?

          begin
            Familia::JsonSerializer.parse(raw)
          rescue Familia::SerializerError
            raw
          end
        end
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
