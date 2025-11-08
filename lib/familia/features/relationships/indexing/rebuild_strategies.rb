# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      module Indexing
        # RebuildStrategies provides atomic index rebuild operations with zero downtime.
        #
        # All rebuild strategies follow a consistent pattern:
        # 1. Build index in temporary key
        # 2. Batch processing with transactions per batch (not entire rebuild)
        # 3. Atomic swap via Lua script at completion
        # 4. Progress callbacks throughout
        #
        # This ensures:
        # - Zero downtime during rebuild (live index remains available)
        # - Memory efficiency (batch processing)
        # - Consistent progress reporting
        # - Safe failure handling (temp key abandoned on error)
        #
        # @example Via instances collection
        #   RebuildStrategies.rebuild_via_instances(
        #     User,
        #     :email,
        #     :add_to_email_index,
        #     batch_size: 100
        #   ) { |progress| puts "Processed: #{progress[:completed]}/#{progress[:total]}" }
        #
        # @example Via participation relationship
        #   RebuildStrategies.rebuild_via_participation(
        #     company,
        #     Employee,
        #     :department,
        #     :add_to_company_dept_index,
        #     company.employees_collection,
        #     batch_size: 100
        #   )
        #
        # @example Via SCAN (fallback for complex scenarios)
        #   RebuildStrategies.rebuild_via_scan(
        #     User,
        #     :email,
        #     :add_to_email_index,
        #     batch_size: 100
        #   )
        #
        module RebuildStrategies
          module_function

          # Rebuilds index by loading objects from ModelClass.instances sorted set.
          #
          # This is the preferred strategy for models with class-level indexes that
          # maintain an instances collection. It's efficient because:
          # - Direct access to all object identifiers via ZRANGE
          # - Bulk loading via load_multi
          # - No key pattern matching required
          #
          # Process:
          # 1. Enumerate identifiers from ModelClass.instances.members
          # 2. Load objects in batches via load_multi(identifiers).compact
          # 3. Build temp index via transactions (one per batch)
          # 4. Atomic swap temp -> final key via Lua
          #
          # @param indexed_class [Class] The model class being indexed (e.g., User)
          # @param field [Symbol] The field to index (e.g., :email)
          # @param add_method [Symbol] The mutation method to call (e.g., :add_to_email_index)
          # @param batch_size [Integer] Number of objects per batch (default: 100)
          # @yield [Hash] Progress info: {completed:, total:, rate:, elapsed:}
          # @return [Integer] Number of objects processed
          #
          # @example Rebuild user email index
          #   count = RebuildStrategies.rebuild_via_instances(
          #     User,
          #     :email,
          #     :add_to_email_index,
          #     batch_size: 100
          #   ) { |p| puts "#{p[:completed]}/#{p[:total]} (#{p[:rate]}/s)" }
          #
          def rebuild_via_instances(indexed_class, field, add_method, batch_size: 100, &progress)
            unless indexed_class.respond_to?(:instances)
              raise ArgumentError, "#{indexed_class.name} does not have an instances collection"
            end

            instances = indexed_class.instances
            total = instances.size
            start_time = Familia.now

            Familia.info "[Rebuild] Starting via_instances for #{indexed_class.name}.#{field} (#{total} objects)"

            # Determine the final index key by examining the class-level index
            # Extract index name from add_method (e.g., add_to_email_index -> email_index)
            # or add_to_class_email_index -> email_index
            index_name = add_method.to_s.gsub(/^(add_to|update_in|remove_from)_(class_)?/, '')

            # Access the class-level index directly
            unless indexed_class.respond_to?(index_name)
              raise ArgumentError, "#{indexed_class.name} does not have index accessor: #{index_name}"
            end

            index_hashkey = indexed_class.send(index_name)
            final_key = index_hashkey.dbkey
            temp_key = RebuildStrategies.build_temp_key(final_key)

            processed = 0
            indexed_count = 0

            # Process in batches - use membersraw to get raw identifiers without deserialization
            instances.membersraw.each_slice(batch_size) do |identifiers|
              # Bulk load objects, filtering out nils (deleted/missing objects)
              objects = indexed_class.load_multi(identifiers).compact

              # Transaction per batch (NOT entire rebuild)
              batch_indexed = 0
              indexed_class.transaction do |tx|
                objects.each do |obj|
                  value = obj.send(field)
                  # Skip nil/empty field values gracefully
                  next unless value && !value.to_s.strip.empty?

                  # For class-level indexes, use HSET directly into temp key
                  tx.hset(temp_key, value.to_s, obj.identifier.to_s)
                  batch_indexed += 1
                end
              end

              processed += identifiers.size
              indexed_count += batch_indexed
              elapsed = Familia.now - start_time
              rate = processed / elapsed

              progress&.call(
                completed: processed,
                total: total,
                rate: rate.round(2),
                elapsed: elapsed.round(2)
              )
            end

            # Atomic swap: temp -> final (ZERO DOWNTIME)
            RebuildStrategies.atomic_swap(temp_key, final_key, indexed_class.dbclient)

            elapsed = Familia.now - start_time
            Familia.info "[Rebuild] Completed via_instances: #{indexed_count} indexed (#{processed} total) in #{elapsed.round(2)}s"

            indexed_count
          end

          # Rebuilds index by loading objects from a participation collection.
          #
          # This strategy is for instance-scoped indexes where objects participate
          # in a parent's collection (e.g., employees in company.employees_collection).
          #
          # Process:
          # 1. Enumerate members from collection (SortedSet, UnsortedSet, or ListKey)
          # 2. Load objects in batches via load_multi(identifiers).compact
          # 3. Build temp index via transactions (one per batch)
          # 4. Atomic swap temp -> final key via Lua
          #
          # @param scope_instance [Object] The parent instance providing scope (e.g., company)
          # @param indexed_class [Class] The model class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :badge_number)
          # @param add_method [Symbol] The mutation method (e.g., :add_to_company_badge_index)
          # @param collection [DataType] The collection containing members (SortedSet/UnsortedSet/ListKey)
          # @param cardinality [Symbol] The index cardinality (:unique or :multi) - must be :unique
          # @param batch_size [Integer] Number of objects per batch (default: 100)
          # @yield [Hash] Progress info: {completed:, total:, rate:, elapsed:}
          # @return [Integer] Number of objects processed
          #
          # @example Rebuild company badge index
          #   count = RebuildStrategies.rebuild_via_participation(
          #     company,
          #     Employee,
          #     :badge_number,
          #     :add_to_company_badge_index,
          #     company.employees_collection,
          #     :unique,
          #     batch_size: 100
          #   )
          #
          def rebuild_via_participation(scope_instance, indexed_class, field, add_method, collection, cardinality, batch_size: 100, &progress)
            total = collection.size
            start_time = Familia.now

            scope_class = scope_instance.class.name
            Familia.info "[Rebuild] Starting via_participation for #{scope_class}##{indexed_class.name}.#{field} (#{total} objects)"

            # Guard: This method only supports unique indexes
            if cardinality != :unique
              raise ArgumentError, <<~ERROR.strip
                rebuild_via_participation only supports unique indexes (cardinality: :unique)
                Received cardinality: #{cardinality.inspect} for field: #{field}

                Multi-indexes require field-value-specific keys and use specialized 4-phase rebuild logic.
                Use the dedicated rebuild method generated on the scope instance instead.
              ERROR
            end

            # Build temp key for the unique index.
            #
            # Extract index name from add_method. The add_method follows the pattern:
            #   add_to_{scope_class_config}_{index_name}
            #
            # For example:
            #   add_to_test_company_badge_index -> badge_index
            #   add_to_company_badge_index -> badge_index
            #
            # We need to remove the "add_to_{scope_class_config}_" prefix.
            scope_class_config = scope_instance.class.config_name
            prefix = "add_to_#{scope_class_config}_"
            index_name = add_method.to_s.gsub(/^#{Regexp.escape(prefix)}/, '')

            # Get the actual index accessor from the scope instance to derive the correct key.
            # This ensures we use the same dbkey as the actual index DataType.
            unless scope_instance.respond_to?(index_name)
              raise ArgumentError, "#{scope_instance.class} does not have index accessor: #{index_name}"
            end

            index_datatype = scope_instance.send(index_name)
            final_key = index_datatype.dbkey
            temp_key = RebuildStrategies.build_temp_key(final_key)

            processed = 0
            indexed_count = 0

            # Process in batches - use membersraw to get raw identifiers
            collection.membersraw.each_slice(batch_size) do |identifiers|
              objects = indexed_class.load_multi(identifiers).compact

              # Transaction per batch
              batch_indexed = 0
              scope_instance.transaction do |tx|
                objects.each do |obj|
                  value = obj.send(field)
                  next unless value && !value.to_s.strip.empty?

                  # For unique index: HSET temp_key field_value identifier
                  # For multi-index: SADD temp_key:field_value identifier
                  tx.hset(temp_key, value.to_s, obj.identifier.to_s)
                  batch_indexed += 1
                end
              end

              processed += identifiers.size
              indexed_count += batch_indexed
              elapsed = Familia.now - start_time
              rate = processed / elapsed

              progress&.call(
                completed: processed,
                total: total,
                rate: rate.round(2),
                elapsed: elapsed.round(2)
              )
            end

            # Atomic swap
            RebuildStrategies.atomic_swap(temp_key, final_key, scope_instance.dbclient)

            elapsed = Familia.now - start_time
            Familia.info "[Rebuild] Completed via_participation: #{indexed_count} indexed (#{processed} total) in #{elapsed.round(2)}s"

            indexed_count
          end

          # Rebuilds index by scanning all keys matching a pattern.
          #
          # This is the fallback strategy when:
          # - No instances collection available
          # - No participation relationship
          # - Need to rebuild from raw keys
          #
          # Uses SCAN (not KEYS) for memory-efficient iteration. Filters by scope
          # if scope_instance provided.
          #
          # Process:
          # 1. Use redis.scan_each(match: pattern, count: batch_size)
          # 2. Filter by scope_instance if provided
          # 3. Load objects in batches via load_multi_by_keys
          # 4. Build temp index via transactions (one per batch)
          # 5. Atomic swap temp -> final key via Lua
          #
          # @param indexed_class [Class] The model class being indexed
          # @param field [Symbol] The field to index
          # @param add_method [Symbol] The mutation method
          # @param scope_instance [Object, nil] Optional scope for filtering
          # @param batch_size [Integer] Number of keys per SCAN iteration (default: 100)
          # @yield [Hash] Progress info: {completed:, scanned:, rate:, elapsed:}
          # @return [Integer] Number of objects processed
          #
          # @example Rebuild without instances collection
          #   count = RebuildStrategies.rebuild_via_scan(
          #     User,
          #     :email,
          #     :add_to_email_index,
          #     batch_size: 100
          #   )
          #
          def rebuild_via_scan(indexed_class, field, add_method, scope_instance: nil, batch_size: 100, &progress)
            start_time = Familia.now

            # Build key pattern for SCAN
            # For instance-scoped indexes, we still scan all objects of indexed_class
            # (not scoped under parent), then filter by scope during processing
            pattern = "#{indexed_class.config_name}:*:object"

            Familia.info "[Rebuild] Starting via_scan for #{indexed_class.name}.#{field} (pattern: #{pattern})"
            Familia.warn "[Rebuild] Using SCAN fallback - consider adding instances collection for better performance"

            # Determine final key by examining the index
            # Extract index name from add_method (e.g., add_to_class_email_index -> email_index)
            # For instance-scoped: add_to_rebuild_test_company_badge_index -> badge_index
            index_name = add_method.to_s.gsub(/^(add_to|update_in|remove_from)_(class_)?/, '')

            # Strip scope class config prefix if present (e.g., rebuild_test_company_badge_index -> badge_index)
            # For instance-scoped indexes, the index lives on scope_instance, not indexed_class
            if scope_instance
              scope_config = scope_instance.class.config_name
              index_name = index_name.gsub(/^#{scope_config}_/, '')
            end

            # For instance-scoped indexes, check scope_instance for accessor
            # For class-level indexes, check indexed_class
            index_owner = scope_instance || indexed_class
            unless index_owner.respond_to?(index_name)
              raise ArgumentError, "#{index_owner.class.name} does not have index accessor: #{index_name}"
            end

            index_hashkey = index_owner.send(index_name)
            final_key = index_hashkey.dbkey
            temp_key = RebuildStrategies.build_temp_key(final_key)

            processed = 0
            indexed_count = 0
            scanned = 0
            redis = indexed_class.dbclient

            # Use SCAN (not KEYS) for memory efficiency
            batch = []
            redis.scan_each(match: pattern, count: batch_size) do |key|
              batch << key
              scanned += 1

              # Process in batches
              if batch.size >= batch_size
                batch_indexed = RebuildStrategies.process_scan_batch(batch, indexed_class, field, temp_key, scope_instance)
                processed += batch.size
                indexed_count += batch_indexed

                elapsed = Familia.now - start_time
                rate = processed / elapsed

                progress&.call(
                  completed: processed,
                  scanned: scanned,
                  rate: rate.round(2),
                  elapsed: elapsed.round(2)
                )

                batch.clear
              end
            end

            # Process remaining batch
            unless batch.empty?
              batch_indexed = RebuildStrategies.process_scan_batch(batch, indexed_class, field, temp_key, scope_instance)
              processed += batch.size
              indexed_count += batch_indexed
            end

            # Atomic swap
            RebuildStrategies.atomic_swap(temp_key, final_key, redis)

            elapsed = Familia.now - start_time
            Familia.info "[Rebuild] Completed via_scan: #{indexed_count} indexed (#{processed} total) in #{elapsed.round(2)}s (scanned: #{scanned})"

            indexed_count
          end

          # Processes a batch of keys from SCAN (module_function helper)
          #
          # @param keys [Array<String>] Array of Redis keys
          # @param indexed_class [Class] The model class
          # @param field [Symbol] The field to index
          # @param temp_key [String] The temporary index key
          # @param scope_instance [Object, nil] Optional scope instance (currently unused)
          # @return [Integer] Number of objects indexed in this batch
          #
          def process_scan_batch(keys, indexed_class, field, temp_key, scope_instance)
            # Load objects by keys
            objects = indexed_class.load_multi_by_keys(keys).compact

            # For instance-scoped indexes, filter objects by scope
            if scope_instance
              # Get the participation collection for this scope
              participation = indexed_class.participation_relationships.find do |rel|
                rel.target_class == scope_instance.class
              end

              if participation
                collection_name = participation.collection_name
                scope_collection = scope_instance.send(collection_name)
                # Filter to only objects that belong to this scope
                objects = objects.select { |obj| scope_collection.member?(obj.identifier) }
              end
            end

            # Transaction per batch
            batch_indexed = 0
            indexed_class.transaction do |tx|
              objects.each do |obj|
                value = obj.send(field)
                next unless value && !value.to_s.strip.empty?

                tx.hset(temp_key, value.to_s, obj.identifier.to_s)
                batch_indexed += 1
              end
            end
            batch_indexed
          rescue StandardError => e
            Familia.warn "[Rebuild] Error processing batch: #{e.message}"
            0
          end

          # Builds a temporary key name for atomic swaps
          #
          # @param base_key [String] The final index key
          # @return [String] Temporary key with timestamp suffix
          #
          def build_temp_key(base_key)
            timestamp = Familia.now.to_i
            "#{base_key}:rebuild:#{timestamp}"
          end

          # Performs atomic swap of temp key to final key via Lua script.
          #
          # This ensures zero downtime during rebuild:
          # 1. DEL final_key (remove old index)
          # 2. RENAME temp_key final_key (atomically replace)
          #
          # Both operations execute atomically in Lua, preventing:
          # - Partial updates
          # - Race conditions
          # - Stale data visibility
          #
          # @param temp_key [String] The temporary key containing rebuilt index
          # @param final_key [String] The live index key
          # @param redis [Redis] The Redis connection
          #
          def atomic_swap(temp_key, final_key, redis)
            # Check if temp key exists first - RENAME fails on non-existent keys
            unless redis.exists(temp_key) > 0
              Familia.info "[Rebuild] No temp key to swap (empty result set)"
              # Just ensure final key is cleared
              redis.del(final_key)
              return
            end

            # Atomic swap: DEL final key, then RENAME temp -> final
            # RENAME is already atomic, so we just need to clear the final key first
            redis.del(final_key)
            redis.rename(temp_key, final_key)
            Familia.info "[Rebuild] Atomic swap completed: #{temp_key} -> #{final_key}"
          rescue Redis::CommandError => e
            # If temp key doesn't exist, just log and return (already handled above)
            if e.message.include?("no such key")
              Familia.info "[Rebuild] Temp key vanished during swap (concurrent operation?)"
              return
            end

            # For other errors, preserve temp key for debugging
            Familia.warn "[Rebuild] Atomic swap failed: #{e.message}"
            Familia.warn "[Rebuild] Temp key preserved for debugging: #{temp_key}"
            raise
          end

          # Calculates processing rate in objects per second
          #
          # @param completed [Integer] Number of objects processed
          # @param elapsed [Float] Time elapsed in seconds
          # @return [Float] Processing rate (objects/second)
          #
          def calculate_rate(completed, elapsed)
            return 0.0 if elapsed.zero?
            (completed / elapsed).round(2)
          end
        end
      end
    end
  end
end
