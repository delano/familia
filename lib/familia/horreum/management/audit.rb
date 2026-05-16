# lib/familia/horreum/management/audit.rb
#
# frozen_string_literal: true

require 'set' # stdlib in Ruby 3.2/3.3; autoloaded core in 3.4+. Required for Set.new usages below.

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
      # @param scanned_identifiers [Array<String>, nil] Internal optimization
      #   parameter; do not rely on this from external callers. When provided
      #   (e.g. threaded through from health_check), skips the per-index SCAN
      #   pass. When omitted, each index computes its own scan.
      # @param loaded_objects [Array<Horreum>, nil] Internal optimization
      #   parameter aligned with scanned_identifiers. When provided, skips
      #   the per-index load_multi call.
      # @return [Array<Hash>] [{index_name:, stale: [...], missing: [...]}]
      #
      def audit_unique_indexes(scanned_identifiers: nil, loaded_objects: nil)
        return [] unless respond_to?(:indexing_relationships)

        indexing_relationships.select do |r|
          r.cardinality == :unique && r.within.nil?
        end.map do |rel|
          audit_single_unique_index(
            rel,
            scanned_identifiers: scanned_identifiers,
            loaded_objects: loaded_objects,
          )
        end
      end

      # Audits all multi indexes.
      #
      # For each multi index:
      # - SCANs for per-value set keys
      # - Checks that each member exists and field value matches
      # - Detects orphaned set keys (sets for values no object has)
      #
      # @param scanned_identifiers [Array<String>, nil] Internal optimization
      #   parameter; do not rely on this from external callers. When provided,
      #   skips the per-index SCAN pass used to detect missing buckets.
      # @param loaded_objects [Array<Horreum>, nil] Internal optimization
      #   parameter aligned with scanned_identifiers.
      # @return [Array<Hash>] [{index_name:, stale_members: [], orphaned_keys: []}]
      #
      def audit_multi_indexes(scanned_identifiers: nil, loaded_objects: nil)
        return [] unless respond_to?(:indexing_relationships)

        indexing_relationships.select do |r|
          r.cardinality == :multi
        end.map do |rel|
          audit_single_multi_index(
            rel,
            scanned_identifiers: scanned_identifiers,
            loaded_objects: loaded_objects,
          )
        end
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

        participation_relationships.flat_map do |rel|
          if rel.target_class == self
            # Class-level participation (class_participates_in)
            [audit_class_participation(rel, sample_size: sample_size)]
          else
            # Instance-level participation (participates_in TargetClass, :collection)
            audit_instance_participations(rel, sample_size: sample_size)
          end
        end
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

      # Audits drift between the `instances` ZSET and class-level unique
      # indexes that per-registry audits cannot surface alone.
      #
      # For every live identifier in `instances`, verifies that each
      # class-level unique index has an entry keyed by the object's current
      # field value and that entry points back to the same identifier.
      #
      # Two failure modes are detected:
      # - `in_instances_missing_unique_index`: live object has a populated
      #   indexed field but no corresponding entry exists in the index.
      # - `index_points_to_wrong_identifier`: entry exists but references a
      #   different identifier (split-brain between two objects).
      #
      # Scope is limited to class-level unique indexes (`within` nil or
      # `:class`). Multi-indexes are covered by audit_multi_indexes;
      # instance-scoped unique indexes are out of scope for this audit.
      #
      # @param batch_size [Integer] load_multi batch size (default: 100)
      # @yield [Hash] Progress: {phase: :cross_references, current:, total:}
      # @return [Hash] {in_instances_missing_unique_index: [], index_points_to_wrong_identifier: [], status:}
      #
      def audit_cross_references(batch_size: 100, &progress)
        empty_result = {
          in_instances_missing_unique_index: [],
          index_points_to_wrong_identifier: [],
          status: :ok,
        }

        return empty_result unless respond_to?(:indexing_relationships)

        class_unique_rels = indexing_relationships.select do |rel|
          rel.cardinality == :unique && (rel.within.nil? || rel.within == :class)
        end
        return empty_result if class_unique_rels.empty?

        instance_ids = instances.members
        total = instance_ids.size
        processed = 0

        in_instances_missing_unique_index = []
        index_points_to_wrong_identifier = []

        instance_ids.each_slice(batch_size) do |batch|
          objects = load_multi(batch)
          processed += batch.size

          # Per unique index, collect (identifier, field_value) pairs from live
          # objects in this batch and resolve them with a single HMGET round
          # trip instead of one HGET per (object x index) combination.
          class_unique_rels.each do |rel|
            next unless respond_to?(rel.index_name)

            lookups = []
            batch.zip(objects).each do |identifier, obj|
              next unless obj

              field_value = obj.send(rel.field)
              next if field_value.nil? || field_value.to_s.strip.empty?

              lookups << [identifier, field_value.to_s]
            end
            next if lookups.empty?

            index_dbkey = send(rel.index_name).dbkey
            raw_values = dbclient.hmget(index_dbkey, *lookups.map(&:last))

            lookups.each_with_index do |(identifier, field_value_str), idx|
              indexed_id = deserialize_index_value(raw_values[idx])

              if indexed_id.nil?
                in_instances_missing_unique_index << {
                  identifier: identifier,
                  index_name: rel.index_name,
                  field_value: field_value_str,
                  existing_index_value: nil,
                }
              elsif indexed_id != identifier
                index_points_to_wrong_identifier << {
                  index_name: rel.index_name,
                  field_value: field_value_str,
                  expected_id: identifier,
                  index_id: indexed_id,
                }
              end
            end
          end

          progress&.call(phase: :cross_references, current: processed, total: total)
        end

        status = if in_instances_missing_unique_index.empty? && index_points_to_wrong_identifier.empty?
          :ok
        else
          :issues_found
        end

        {
          in_instances_missing_unique_index: in_instances_missing_unique_index,
          index_points_to_wrong_identifier: index_points_to_wrong_identifier,
          status: status,
        }
      end

      # Runs all audits and wraps results in an AuditReport.
      #
      # The related_fields audit is opt-in via `audit_collections: true`
      # because it performs an additional SCAN per instance-level field.
      # When omitted (or false), AuditReport#related_fields is nil which
      # signals "not checked" rather than "checked and clean".
      #
      # The cross-references audit is opt-in via `check_cross_refs: true`.
      # It walks every identifier in the instances ZSET and cross-checks
      # each class-level unique index; skipping it keeps the default
      # health_check fast. When omitted (or false), AuditReport#cross_references
      # is nil, signalling "not checked".
      #
      # @param batch_size [Integer] SCAN batch size for instances audit
      # @param sample_size [Integer, nil] Sample size for participation audit
      # @param audit_collections [Boolean] When true, also run audit_related_fields
      # @param check_cross_refs [Boolean] When true, also run audit_cross_references
      # @yield [Hash] Progress from audit_instances
      # @return [AuditReport]
      #
      def health_check(batch_size: 100, sample_size: nil, audit_collections: false,
                       check_cross_refs: false, &progress)
        start_time = Familia.now

        inst = audit_instances(batch_size: batch_size, &progress)

        # Reuse the SCAN pass and the HGETALL pipeline across both index
        # audits. Without this, a model with N unique indexes and M multi
        # indexes would trigger N+M additional SCANs and load_multi round
        # trips during their "missing" phases.
        has_indexes = respond_to?(:indexing_relationships) && indexing_relationships.any? do |r|
          (r.cardinality == :unique && r.within.nil?) || r.cardinality == :multi
        end

        if has_indexes
          shared_ids = scan_identifiers(batch_size: batch_size).to_a
          shared_objects = load_multi(shared_ids)
        else
          shared_ids = nil
          shared_objects = nil
        end

        uniq = audit_unique_indexes(
          scanned_identifiers: shared_ids,
          loaded_objects: shared_objects,
        )
        multi = audit_multi_indexes(
          scanned_identifiers: shared_ids,
          loaded_objects: shared_objects,
        )
        parts = audit_participations(sample_size: sample_size)
        related = audit_collections ? audit_related_fields : nil
        cross_refs = check_cross_refs ? audit_cross_references(batch_size: batch_size, &progress) : nil

        duration = Familia.now - start_time

        AuditReport.new(
          model_class: name,
          audited_at: start_time,
          instances: inst,
          unique_indexes: uniq,
          multi_indexes: multi,
          participations: parts,
          related_fields: related,
          cross_references: cross_refs,
          duration: duration,
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
        cursor = '0'

        loop do
          cursor, keys = dbclient.scan(cursor, match: pattern, count: batch_size)
          keys.each do |key|
            identifier = extract_identifier_from_key(key)
            next if identifier.nil? || identifier.empty?

            ids << identifier
          end
          progress&.call(phase: :scanning, current: ids.size, total: nil)
          break if cursor == '0'
        end

        ids
      end

      # Audit a single unique index (class-level).
      #
      # @param rel [IndexingRelationship]
      # @param scanned_identifiers [Array<String>, nil] Optional cached SCAN
      #   result; when provided, skips the per-index SCAN pass.
      # @param loaded_objects [Array<Horreum>, nil] Optional cached load_multi
      #   result aligned with scanned_identifiers.
      # @return [Hash] {index_name:, stale: [], missing: []}
      #
      def audit_single_unique_index(rel, scanned_identifiers: nil, loaded_objects: nil)
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
        all_identifiers = scanned_identifiers || scan_identifiers.to_a
        all_objects = loaded_objects || load_multi(all_identifiers)

        all_identifiers.each_with_index do |identifier, idx|
          obj = all_objects[idx]
          next unless obj

          value = obj.send(field)
          next if value.nil? || value.to_s.strip.empty?

          missing << { identifier: identifier, field_value: value.to_s } unless indexed_values.include?(value.to_s)
        end

        { index_name: index_name, stale: stale, missing: missing }
      end

      # Audit a single multi index.
      #
      # Class-level multi-indexes (within: nil or within: :class) and
      # instance-scoped multi-indexes (within: SomeClass) are both fully
      # audited. The class-level path SCANs a single bucket namespace and
      # cross-checks it against live objects on this class. The
      # instance-scoped path SCANs across all scope instances, partitions
      # the discovered bucket keys by scope id, and uses the participation
      # relationship (if present) to detect missing entries.
      #
      # @param rel [IndexingRelationship]
      # @param scanned_identifiers [Array<String>, nil] Optional cached SCAN result.
      # @param loaded_objects [Array<Horreum>, nil] Optional cached load_multi result.
      # @return [Hash] {index_name:, stale_members: [], missing: [], orphaned_keys: [], status:}
      #
      def audit_single_multi_index(rel, scanned_identifiers: nil, loaded_objects: nil)
        if rel.class_level?
          audit_class_level_multi_index(
            rel,
            scanned_identifiers: scanned_identifiers,
            loaded_objects: loaded_objects,
          )
        else
          audit_instance_scoped_multi_index(rel)
        end
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
      # @param scanned_identifiers [Array<String>, nil] Optional cached SCAN result.
      # @param loaded_objects [Array<Horreum>, nil] Optional cached load_multi result.
      # @return [Hash] {index_name:, stale_members:, missing:, orphaned_keys:, status:}
      #
      def audit_class_level_multi_index(rel, scanned_identifiers: nil, loaded_objects: nil)
        bucket_entries = discover_multi_index_buckets(rel)
        discovered_field_values = bucket_entries.keys.to_set

        stale_members = detect_multi_index_stale_members(rel, bucket_entries)
        missing, actual_field_values = detect_multi_index_missing(
          rel,
          discovered_field_values,
          scanned_identifiers: scanned_identifiers,
          loaded_objects: loaded_objects,
        )
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
        bucket_pattern = "#{prefix}#{Familia.delim}#{rel.index_name}#{Familia.delim}*"
        bucket_prefix = "#{prefix}#{Familia.delim}#{rel.index_name}#{Familia.delim}"
        bucket_entries = {}

        # Batch SCAN results and pipeline SMEMBERS to collapse one round trip
        # per bucket key into one round trip per slice of 100 keys.
        dbclient.scan_each(match: bucket_pattern).each_slice(100) do |keys|
          valid_keys = keys.select { |k| k.start_with?(bucket_prefix) }
          next if valid_keys.empty?

          members_batch = dbclient.pipelined do |pipe|
            valid_keys.each { |k| pipe.smembers(k) }
          end

          valid_keys.each_with_index do |key, idx|
            field_value = key[bucket_prefix.length..]
            next if field_value.nil? || field_value.empty?

            bucket_entries[field_value] = {
              key: key,
              identifiers: deserialize_index_members(members_batch[idx]),
            }
          end
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
      # @param scanned_identifiers [Array<String>, nil] Optional cached SCAN result.
      # @param loaded_objects [Array<Horreum>, nil] Optional cached load_multi result.
      # @return [Array(Array<Hash>, Set<String>)] missing entries and the set of
      #   field values observed on live objects
      #
      def detect_multi_index_missing(rel, discovered_field_values, scanned_identifiers: nil, loaded_objects: nil)
        all_identifiers = scanned_identifiers || scan_identifiers.to_a
        all_objects = loaded_objects || load_multi(all_identifiers)
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

      # Audit an instance-scoped multi-index across every scope instance.
      #
      # Key layout: "{scope_prefix}:{scope_id}:{index_name}:{field_value}"
      # SCAN pattern: "{scope_prefix}:*:{index_name}:*"
      #
      # Three failure modes are detected:
      #   - stale_members: bucket member object missing or field value drifted
      #   - orphaned_keys: scope instance no longer exists, or bucket field
      #     value is not held by any live participant for that scope
      #   - missing: live participant has a field value but no bucket entry
      #     in the scope it belongs to (requires participation relationship)
      #
      # Detecting "missing" requires walking each scope instance's
      # participation collection to discover which indexed objects belong
      # to which scope. When the indexed class does not declare a
      # `participates_in scope_class, :collection_name` relationship, the
      # missing dimension is set to `:not_audited` and a debug message
      # explains why.
      #
      # @param rel [IndexingRelationship]
      # @return [Hash] {index_name:, stale_members:, missing:, orphaned_keys:, status:}
      #
      def audit_instance_scoped_multi_index(rel)
        scope_class = Familia.resolve_class(rel.scope_class)

        bucket_entries = discover_instance_scoped_buckets(rel, scope_class)
        scope_ids = bucket_entries.values.map { |e| e[:scope_id] }.uniq
        scope_exists_flags = batch_check_scope_existence(scope_class, scope_ids)

        stale_members, orphaned_from_scope = inspect_instance_scoped_buckets(
          rel, bucket_entries, scope_exists_flags
        )

        missing, missing_status = detect_instance_scoped_missing(
          rel, scope_class, bucket_entries, scope_exists_flags
        )

        orphaned_from_field_value = detect_instance_scoped_orphaned_buckets(
          rel, scope_class, bucket_entries, scope_exists_flags
        )

        orphaned_keys = orphaned_from_scope + orphaned_from_field_value

        status = if stale_members.empty? && missing.empty? && orphaned_keys.empty?
          :ok
        else
          :issues_found
        end

        result = {
          index_name: rel.index_name,
          stale_members: stale_members,
          missing: missing,
          orphaned_keys: orphaned_keys,
          status: status,
        }
        # Surface a sub-status when the "missing" dimension could not be
        # audited so callers can distinguish "checked and clean" from
        # "not checked due to missing participation".
        result[:missing_status] = missing_status if missing_status != :ok
        result
      end

      # SCAN for instance-scoped bucket keys and load their members.
      #
      # @param rel [IndexingRelationship]
      # @param scope_class [Class]
      # @return [Hash{String => Hash}] full_key => {key:, scope_id:, field_value:, identifiers:}
      #
      def discover_instance_scoped_buckets(rel, scope_class)
        scope_prefix = "#{scope_class.prefix}#{Familia.delim}"
        marker = "#{Familia.delim}#{rel.index_name}#{Familia.delim}"
        pattern = "#{scope_prefix}*#{marker}*"
        bucket_entries = {}

        # Use the scope class's dbclient so multi-database setups address
        # the right Redis instance for the scope namespace.
        client = scope_class.dbclient

        # Batch SCAN results and pipeline SMEMBERS to collapse a round trip
        # per bucket key into a round trip per slice of 100 keys.
        client.scan_each(match: pattern).each_slice(100) do |keys|
          parsed = keys.filter_map do |key|
            scope_id, field_value = parse_instance_scoped_bucket_key(key, scope_prefix, marker)
            next nil if scope_id.nil? || scope_id.empty? || field_value.nil? || field_value.empty?

            [key, scope_id, field_value]
          end
          next if parsed.empty?

          members_batch = client.pipelined do |pipe|
            parsed.each { |(key, _sid, _fv)| pipe.smembers(key) }
          end

          parsed.each_with_index do |(key, scope_id, field_value), idx|
            bucket_entries[key] = {
              key: key,
              scope_id: scope_id,
              field_value: field_value,
              identifiers: deserialize_index_members(members_batch[idx]),
            }
          end
        end

        bucket_entries
      end

      # Splits a bucket key into (scope_id, field_value).
      #
      # The key is structured as "{scope_prefix}{scope_id}{marker}{field_value}"
      # where marker is "{delim}{index_name}{delim}". The first occurrence of
      # the marker is used to support identifiers and field values that
      # themselves contain the delimiter character.
      #
      # @param key [String]
      # @param scope_prefix [String]
      # @param marker [String]
      # @return [Array(String, String), Array(nil, nil)]
      #
      def parse_instance_scoped_bucket_key(key, scope_prefix, marker)
        return [nil, nil] unless key.start_with?(scope_prefix)

        rest = key[scope_prefix.length..]
        marker_pos = rest.index(marker)
        return [nil, nil] unless marker_pos

        scope_id = rest[0...marker_pos]
        field_value = rest[(marker_pos + marker.length)..]
        [scope_id, field_value]
      end

      # Batch-checks scope instance existence via pipelined EXISTS.
      #
      # @param scope_class [Class]
      # @param scope_ids [Array<String>]
      # @return [Hash{String => Boolean}]
      #
      def batch_check_scope_existence(scope_class, scope_ids)
        flags = {}
        return flags if scope_ids.empty?

        scope_ids.each_slice(100) do |slice|
          results = scope_class.dbclient.pipelined do |pipe|
            slice.each { |id| pipe.exists(scope_class.dbkey(id)) }
          end
          slice.each_with_index do |id, idx|
            flags[id] = results[idx].to_i.positive?
          end
        end

        flags
      end

      # Inspects each instance-scoped bucket's members for staleness.
      #
      # For buckets whose scope still exists, classify members via
      # classify_multi_index_entry. For buckets whose scope is missing,
      # mark the entire bucket as orphaned with reason :scope_missing.
      #
      # @return [Array(Array<Hash>, Array<Hash>)] (stale_members, orphaned_from_scope)
      #
      def inspect_instance_scoped_buckets(rel, bucket_entries, scope_exists_flags)
        stale_members = []
        orphaned = []

        bucket_entries.each_value do |entry|
          unless scope_exists_flags[entry[:scope_id]]
            orphaned << {
              field_value: entry[:field_value],
              key: entry[:key],
              scope_id: entry[:scope_id],
              reason: :scope_missing,
            }
            next
          end

          identifiers = entry[:identifiers].map(&:to_s)
          next if identifiers.empty?

          objects = load_multi(identifiers)
          identifiers.each_with_index do |identifier, idx|
            classification = classify_multi_index_entry(rel, entry[:field_value], identifier, objects[idx])
            next unless classification

            classification[:scope_id] = entry[:scope_id]
            stale_members << classification
          end
        end

        [stale_members, orphaned]
      end

      # Detects buckets whose field_value is no longer held by any live
      # participant in that scope.
      #
      # Without a participation relationship from this class to the scope
      # class, we cannot determine which participants belong to which scope,
      # so this dimension is skipped (the prior :scope_missing check still
      # surfaces fully orphaned buckets).
      #
      # @return [Array<Hash>]
      #
      def detect_instance_scoped_orphaned_buckets(rel, scope_class, bucket_entries, scope_exists_flags)
        participation = find_participation_to_scope(scope_class)
        return [] unless participation

        # field_values_per_scope: { scope_id => Set<String> } observed on live participants
        field_values_per_scope = collect_field_values_per_scope(rel, scope_class, participation)

        orphaned = []
        bucket_entries.each_value do |entry|
          # Already counted by inspect_instance_scoped_buckets when scope is missing.
          next unless scope_exists_flags[entry[:scope_id]]

          observed = field_values_per_scope[entry[:scope_id]] || Set.new
          next if observed.include?(entry[:field_value])

          orphaned << {
            field_value: entry[:field_value],
            key: entry[:key],
            scope_id: entry[:scope_id],
            reason: :field_value_unheld,
          }
        end

        orphaned
      end

      # Detects live participants whose bucket entry is absent.
      #
      # @return [Array(Array<Hash>, Symbol)] (missing, sub_status)
      #
      def detect_instance_scoped_missing(rel, scope_class, bucket_entries, scope_exists_flags)
        participation = find_participation_to_scope(scope_class)
        return [[], :not_audited] unless participation

        unless scope_class.respond_to?(:instances)
          Familia.debug "[audit_instance_scoped_multi_index] #{name}##{rel.index_name}: " \
                        "scope class #{scope_class.name} has no instances collection; " \
                        'missing detection requires enumerating scope instances'
          return [[], :no_scope_instances]
        end

        missing = []
        scope_ids = enumerate_scope_ids(scope_class, scope_exists_flags)

        scope_ids.each do |scope_id|
          scope_instance = scope_class.find_by_id(scope_id)
          next unless scope_instance

          collection = scope_instance.send(participation.collection_name)
          member_ids = participation_collection_members(collection)
          next if member_ids.empty?

          member_objects = load_multi(member_ids)
          member_ids.each_with_index do |identifier, idx|
            obj = member_objects[idx]
            next unless obj

            value = obj.send(rel.field)
            next if value.nil? || value.to_s.strip.empty?

            expected_field_value = value.to_s
            expected_key = build_instance_scoped_bucket_key(scope_class, scope_id, rel.index_name, expected_field_value)
            bucket = bucket_entries[expected_key]
            next if bucket && bucket[:identifiers].any? { |m| m.to_s == identifier.to_s }

            missing << {
              identifier: identifier,
              field_value: expected_field_value,
              scope_class: scope_class.name,
              scope_id: scope_id,
            }
          end
        end

        [missing, :ok]
      end

      # Aggregates the field values present per scope instance via the
      # participation collection. Used to decide which buckets are orphaned
      # by virtue of no live participant holding their field_value.
      #
      # @return [Hash{String => Set<String>}]
      #
      def collect_field_values_per_scope(rel, scope_class, participation)
        result = Hash.new { |h, k| h[k] = Set.new }
        return result unless scope_class.respond_to?(:instances)

        scope_class.instances.members.each do |scope_id|
          scope_instance = scope_class.find_by_id(scope_id)
          next unless scope_instance

          collection = scope_instance.send(participation.collection_name)
          member_ids = participation_collection_members(collection)
          next if member_ids.empty?

          load_multi(member_ids).each do |obj|
            next unless obj

            value = obj.send(rel.field)
            next if value.nil? || value.to_s.strip.empty?

            result[scope_id] << value.to_s
          end
        end

        result
      end

      # Looks up the indexed-class participation pointing at the scope class.
      #
      # Returns nil when the indexed class does not declare a
      # `participates_in scope_class, :collection_name` relationship,
      # which makes per-scope membership inference impossible.
      #
      # @return [ParticipationRelationship, nil]
      #
      def find_participation_to_scope(scope_class)
        return nil unless respond_to?(:participation_relationships)

        participation_relationships.find { |rel| rel.target_class == scope_class }
      end

      # Enumerate the set of scope ids worth inspecting for "missing"
      # detection. Includes:
      #   - every scope id we already saw a bucket for
      #   - every scope id in the scope class's instances timeline
      #
      # @return [Array<String>]
      #
      def enumerate_scope_ids(scope_class, scope_exists_flags)
        from_buckets = scope_exists_flags.select { |_, v| v }.keys
        from_instances = scope_class.instances.members.to_a
        (from_buckets + from_instances).uniq
      end

      # Returns members of a participation collection in a type-agnostic
      # way. Falls back to to_a when the DataType does not expose members.
      #
      # @return [Array<String>]
      #
      def participation_collection_members(collection)
        if collection.respond_to?(:members)
          Array(collection.members)
        elsif collection.respond_to?(:to_a)
          Array(collection.to_a)
        else
          []
        end
      end

      # Rebuilds the expected bucket key for a (scope_id, field_value) pair.
      #
      # @return [String]
      #
      def build_instance_scoped_bucket_key(scope_class, scope_id, index_name, field_value)
        d = Familia.delim
        "#{scope_class.prefix}#{d}#{scope_id}#{d}#{index_name}#{d}#{field_value}"
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
          next if exists?(raw_member)

          stale << {
            identifier: raw_member,
            collection_key: collection_key,
            collection_name: collection_name,
            reason: :object_missing,
          }
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

        # SCAN for all collection keys matching target_prefix{delim}*{delim}collection_name
        pattern = "#{target_class.prefix}#{Familia.delim}*#{Familia.delim}#{collection_name}"
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
          next if exists?(raw_member)

          stale << {
            identifier: raw_member,
            collection_key: collection_key,
            collection_name: rel.collection_name,
            reason: :object_missing,
          }
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

        # Batch SCAN results and pipeline EXISTS checks. Note we use the raw
        # integer EXISTS command here (not the exists? helper) so the result
        # inside the pipeline is aligned positionally with batch_map.values.
        dbclient.scan_each(match: pattern).each_slice(100) do |keys|
          batch_map = keys.each_with_object({}) do |key, map|
            id = extract_identifier_from_key(key, field_name.to_s)
            map[key] = id if id && !id.empty?
          end
          next if batch_map.empty?

          existing_flags = dbclient.pipelined do |pipe|
            batch_map.values.each { |id| pipe.exists(dbkey(id)) }
          end

          batch_map.keys.each_with_index do |key, idx|
            orphaned_keys << key if existing_flags[idx].to_i.zero?
          end
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

      # Deserializes a single raw HMGET value from a unique-index hashkey.
      #
      # Mirrors HashKey#[] semantics for a hashkey without :class or
      # :reference options: nil stays nil, JSON parses to the original Ruby
      # value, and a parse error falls back to the raw string. The result is
      # coerced to a string identifier for comparison against live object IDs.
      #
      # Used by the batched cross-reference audit where raw HMGET is preferred
      # over per-field HGET to reduce round trips.
      #
      # @param raw [String, nil] Single HMGET result value
      # @return [String, nil] identifier string, or nil when raw is nil
      #
      def deserialize_index_value(raw)
        return nil if raw.nil?

        parsed = begin
          Familia::JsonSerializer.parse(raw)
        rescue Familia::SerializerError
          raw
        end

        parsed = parsed.identifier if parsed.respond_to?(:identifier)
        parsed&.to_s
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
        cursor = '0'

        loop do
          cursor, batch = client.scan(cursor, match: pattern, count: batch_size)
          keys.concat(batch)
          break if cursor == '0'
        end

        keys
      end
    end
  end
end
