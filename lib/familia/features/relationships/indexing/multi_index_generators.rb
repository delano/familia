# lib/familia/features/relationships/indexing/multi_index_generators.rb
#
# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      module Indexing
        # Generators for multi-value index (1:many) methods
        #
        # Multi-value indexes use UnsortedSet DataType for grouping objects by field value.
        # Each field value gets its own set of object identifiers.
        #
        # Example:
        #   multi_index :department, :dept_index, within: Company
        #
        # Generates on Company (destination):
        #   - company.sample_from_department(dept, count=1)
        #   - company.find_all_by_department(dept)
        #   - company.dept_index_for(dept_value)
        #   - company.rebuild_dept_index
        #
        # Generates on Employee (self):
        #   - employee.add_to_company_dept_index(company)
        #   - employee.remove_from_company_dept_index(company)
        #   - employee.update_in_company_dept_index(company, old_dept)
        module MultiIndexGenerators
          module_function

          using Familia::Refinements::StylizeWords

          # Maximum recommended length for field values used in index keys.
          # Longer values are allowed but will trigger a warning.
          MAX_FIELD_VALUE_LENGTH = 256

          # Redis type of every per-value bucket key. The factories below
          # build each bucket as a Familia::UnsortedSet.
          BUCKET_KEY_TYPE = 'set'

          # Types a key may hold before the rebuild writes it as a bucket:
          # a set, or "none" when the key does not exist.
          WRITABLE_BUCKET_KEY_TYPES = [BUCKET_KEY_TYPE, 'none'].freeze

          # Validates a field value for use in index key construction.
          # This is for data quality and debugging clarity. It does not make
          # values safe to put in a key pattern: code that builds a SCAN or
          # KEYS pattern from keys like these escapes the literal part with
          # Familia.escape_glob (see .each_index_bucket_slice).
          #
          # @param field_value [Object] The field value to validate
          # @param context [String] Description for warning messages
          # @return [String, nil] The validated string value, or nil if invalid
          def validate_field_value(field_value, context: 'index')
            return nil if field_value.nil?

            str_value = field_value.to_s
            return nil if str_value.strip.empty?

            # Warn on values containing Redis glob pattern characters
            # These are legal but can be confusing when debugging key patterns
            if str_value.match?(/[*?\[\]]/)
              Familia.warn "[#{context}] Field value contains glob pattern characters: #{str_value.inspect}. " \
                           'These are stored as literal characters but may be confusing during debugging.'
            end

            # Warn on control characters (except common whitespace)
            if str_value.match?(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/)
              Familia.warn "[#{context}] Field value contains control characters: #{str_value.inspect}"
            end

            # Warn on excessively long values
            if str_value.length > MAX_FIELD_VALUE_LENGTH
              Familia.warn "[#{context}] Field value exceeds #{MAX_FIELD_VALUE_LENGTH} characters " \
                           "(#{str_value.length} chars): #{str_value[0..50]}..."
            end

            str_value
          end

          # Returns the literal key prefix of the per-value buckets of
          # +index_name+ on +owner+, for example "company:c-1:dept_index:"
          # for a scope instance or "customer:role_index:" for a class.
          #
          # The factories pass a field value through .validate_field_value
          # and name its bucket Familia.join(index_name, validated) under
          # +owner+'s key. This method joins +index_name+ with '' instead,
          # which leaves the index name followed by the delimiter. Every
          # bucket of a non-blank field value starts with that prefix.
          #
          # A blank value is the exception. Validation turns it into nil,
          # which Familia.join drops, so the factories name its bucket
          # "<owner key>:<index_name>" with no trailing delimiter. That key
          # is outside this prefix, and the SCAN in .each_index_bucket_slice
          # does not return it. The instance-scoped add_to_* writes a blank
          # value there; the class-level one skips blank values.
          #
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param index_name [Symbol] name of the index
          # @return [String]
          def bucket_key_prefix(owner, index_name)
            Familia::UnsortedSet.new(Familia.join(index_name, ''), parent: owner).dbkey
          end

          # Yields the keys of the per-value bucket sets whose keys start
          # with +bucket_prefix+, in slices of up to +batch_size+ keys.
          #
          # The prefix is escaped with Familia.escape_glob before the SCAN
          # wildcard is appended, so glob characters in a scope identifier,
          # the class prefix or the delimiter cannot make the pattern match
          # keys outside that literal prefix. SCAN's TYPE option leaves out
          # every key that does not hold a set, the type the factories give
          # each bucket. The Valkey and Redis SCAN command histories both
          # list "Added the `TYPE` subcommand." under 6.0.0, and README.md
          # lists the prerequisite "**Valkey/Redis**: 6.0+". Each returned
          # key must also start with the literal prefix (see
          # .select_index_buckets), a second check before the rebuild
          # deletes it.
          #
          # The rebuild deletes these keys and the audit reads them, so
          # both act on the same keys.
          #
          # @param client [Redis] connection that owns the buckets
          # @param bucket_prefix [String] literal prefix from .bucket_key_prefix
          # @param batch_size [Integer] SCAN count hint and slice size
          # @yieldparam keys [Array<String>] a non-empty slice of bucket keys
          # @return [Enumerator, nil] an Enumerator when no block is given
          def each_index_bucket_slice(client, bucket_prefix, batch_size: 100)
            return enum_for(__method__, client, bucket_prefix, batch_size: batch_size) unless block_given?

            pattern = "#{Familia.escape_glob(bucket_prefix)}*"
            client.scan_each(match: pattern, count: batch_size, type: BUCKET_KEY_TYPE)
                  .each_slice(batch_size) do |keys|
              buckets = select_index_buckets(keys, bucket_prefix)
              yield buckets unless buckets.empty?
            end
            nil
          end

          # Deletes the per-value bucket sets whose keys start with
          # +bucket_prefix+, including buckets for field values that no
          # object holds any more.
          #
          # +live_bucket_keys+ are the keys the rebuild writes after this
          # returns. They are checked with .check_live_bucket_keys! first,
          # so a key the rebuild could not write stops it before any key is
          # deleted.
          #
          # Only the keys .each_index_bucket_slice yields are deleted. A key
          # under the prefix that holds another type is left alone. It was
          # not written as a bucket by this version, and it may belong to a
          # record whose identifier makes its keys share the prefix, such as
          # the hash and list of a record named after a class-level index.
          #
          # @param client [Redis] connection that owns the buckets
          # @param bucket_prefix [String] literal prefix from .bucket_key_prefix
          # @param live_bucket_keys [Array<String>] keys the rebuild writes next
          # @param batch_size [Integer] SCAN count hint, DEL and TYPE batch size
          # @yieldparam key [String] a bucket key that was deleted
          # @yieldparam cleared [Integer] buckets deleted so far
          # @return [Integer] number of bucket keys deleted
          # @raise [Familia::IndexBucketConflictError] see .check_live_bucket_keys!
          def clear_index_buckets(client, bucket_prefix, live_bucket_keys:, batch_size: 100, &on_delete)
            check_live_bucket_keys!(client, live_bucket_keys, batch_size: batch_size)
            cleared = 0

            each_index_bucket_slice(client, bucket_prefix, batch_size: batch_size) do |buckets|
              client.del(*buckets)
              buckets.each do |key|
                cleared += 1
                on_delete&.call(key, cleared)
              end
            end

            cleared
          end

          # Raises Familia::IndexBucketConflictError when one of
          # +bucket_keys+ holds a type other than a set.
          #
          # After the clearing phase, the rebuild adds every object to the
          # bucket of its field value. A key of another type there is not a
          # bucket and may be another record's data, such as the list of a
          # record named after a class-level index when a live field value
          # equals that list's name. SADD into it raises WRONGTYPE, which
          # would stop the rebuild after clearing had already emptied the
          # other buckets, and deleting it could destroy that data. So the
          # rebuild checks every key it will write before it deletes any.
          #
          # @param client [Redis] connection that owns the buckets
          # @param bucket_keys [Array<String>] keys the rebuild will write
          # @param batch_size [Integer] number of TYPE commands per pipeline
          # @return [nil]
          # @raise [Familia::IndexBucketConflictError] naming each such key
          #   and its type
          def check_live_bucket_keys!(client, bucket_keys, batch_size: 100)
            conflicts = {}

            bucket_keys.each_slice(batch_size) do |keys|
              types = client.pipelined do |pipe|
                keys.each { |key| pipe.type(key) }
              end
              keys.zip(types) do |key, type|
                conflicts[key] = type unless WRITABLE_BUCKET_KEY_TYPES.include?(type)
              end
            end
            raise Familia::IndexBucketConflictError, conflicts unless conflicts.empty?

            nil
          end

          # Returns the +keys+ that start with the literal +bucket_prefix+.
          #
          # The check compares bytes. The client returns a key that is not
          # valid UTF-8 as a binary String, and String#start_with? raises
          # Encoding::CompatibilityError for a binary key and a UTF-8 prefix
          # that both hold non-ASCII bytes, as they do when a scope
          # identifier holds invalid UTF-8.
          #
          # @param keys [Array<String>] keys returned by SCAN
          # @param bucket_prefix [String] literal prefix from .bucket_key_prefix
          # @return [Array<String>]
          def select_index_buckets(keys, bucket_prefix)
            prefix = bucket_prefix.b
            keys.select { |key| key.b.start_with?(prefix) }
          end

          # Main setup method that orchestrates multi-value index creation
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index
          # @param index_name [Symbol] Name of the index
          # @param within [Class, Symbol] Scope class for instance-scoped index (required)
          # @param query [Boolean] Whether to generate query methods
          def setup(indexed_class:, field:, index_name:, within:, query:)
            # Determine scope type: class-level or instance-scoped
            scope_class, scope_type = if within == :class
              [indexed_class, :class]
            else
              k = Familia.resolve_class(within)
              [k, :instance]
            end

            # Store metadata for this indexing relationship
            indexed_class.indexing_relationships << IndexingRelationship.new(
              field:             field,
              scope_class:       scope_class,
              within:            within,  # Preserve original (:class or actual class)
              index_name:        index_name,
              query:            query,
              cardinality:       :multi,
            )

            case scope_type
            when :instance
              # Instance-scoped multi-index (existing behavior)
              generate_factory_method(indexed_class, scope_class, index_name)
              generate_query_methods_destination(indexed_class, field, scope_class, index_name) if query
              generate_mutation_methods_self(indexed_class, field, scope_class, index_name)
            when :class
              # Class-level multi-index (new behavior)
              generate_factory_method_class(indexed_class, index_name)
              generate_query_methods_class(indexed_class, field, index_name) if query
              generate_mutation_methods_class(indexed_class, field, index_name)
            end
          end

          # Generates the factory method ON THE SCOPE CLASS (Company when within: Company):
          # - company.index_name_for(field_value) - DataType factory (always needed)
          #
          # This method is required by mutation methods even when query: false
          #
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :dept_index)
          def generate_factory_method(indexed_class, scope_class, index_name)
            actual_scope_class = Familia.resolve_class(scope_class)
            idx_name = index_name

            actual_scope_class.class_eval do
              # Helper method to get index set for a specific field value
              # This acts as a factory for field-value-specific DataTypes
              define_method(:"#{index_name}_for") do |field_value|
                validated = MultiIndexGenerators.validate_field_value(field_value, context: "#{self.class.name}.#{idx_name}")
                index_key = Familia.join(index_name, validated)
                Familia::UnsortedSet.new(index_key, parent: self, class: indexed_class, reference: true)
              end
            end
          end

          # Generates query methods ON THE SCOPE CLASS (Company when within: Company):
          # - company.sample_from_department(dept, count=1) - random sampling
          # - company.find_all_by_department(dept) - all objects
          # - company.rebuild_dept_index - rebuild index
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :department)
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :dept_index)
          def generate_query_methods_destination(indexed_class, field, scope_class, index_name)
            # Resolve scope class using Familia pattern
            actual_scope_class = Familia.resolve_class(scope_class)

            # Get scope_class_config for method naming (needed for rebuild methods)
            scope_class_config = actual_scope_class.config_name

            # Generate instance sampling method (e.g., company.sample_from_department)
            actual_scope_class.class_eval do

              define_method(:"sample_from_#{field}") do |field_value, count = 1|
                index_set = send("#{index_name}_for", field_value) # i.e. UnsortedSet

                # Get random members efficiently (O(1) via SRANDMEMBER with count)
                # Returns array even for count=1 for consistent API
                index_set.sample(count).map do |id|
                  indexed_class.find_by_identifier(id)
                end
              end

              # Generate bulk query method (e.g., company.find_all_by_department)
              define_method(:"find_all_by_#{field}") do |field_value|
                index_set = send("#{index_name}_for", field_value) # i.e. UnsortedSet

                # Get all members from set
                index_set.members.map { |id| indexed_class.find_by_identifier(id) }
              end

              # Generate method to rebuild the multi-value index for this parent instance
              #
              # Multi-indexes create separate sets for each field value, so the rebuild runs in three phases:
              # 1. Loading: Load every object in the participation collection once and cache it,
              #    collecting its field value.
              # 2. Clearing: Check every bucket key phase 3 will write (see @raise), then delete
              #    this scope instance's bucket sets, including those of field values no object
              #    holds any more. A SCAN over the escaped bucket prefix finds them, and only keys
              #    that start with that literal prefix and hold a set are deleted.
              # 3. Rebuilding: Add each cached object to the bucket of its field value
              #    (no reload needed).
              #
              # @param batch_size [Integer] Number of identifiers to process per batch
              # @yield [progress] Optional block called with progress updates
              # @yieldparam progress [Hash] Progress information with keys:
              #   - :phase [Symbol] Current phase (:loading, :clearing, :rebuilding)
              #   - :current [Integer] Current item count
              #   - :total [Integer] Total items (when known)
              #   - :key [String] Bucket key just deleted (:clearing phase only)
              # @return [Integer, nil] Number of objects processed, or nil when the indexed
              #   class has no participation relationship to this scope class
              # @raise [Familia::IndexBucketConflictError] if a bucket key the rebuild will
              #   write holds a type other than set. The rebuild raises before it deletes or
              #   writes anything. The error's #conflicts maps each such key to its type.
              #   The rebuild can run once each of those keys holds a set or no longer exists.
              #
              # @example Basic rebuild
              #   company.rebuild_dept_index
              #
              # @example With progress monitoring
              #   company.rebuild_dept_index do |progress|
              #     puts "#{progress[:phase]}: #{progress[:current]}/#{progress[:total]}"
              #   end
              #
              # @example Memory-conscious rebuild for large collections
              #   # Process in smaller batches to reduce memory footprint
              #   company.rebuild_dept_index(batch_size: 50)
              #
              # @note Memory Considerations:
              #   This method caches all objects in memory during rebuild to avoid duplicate
              #   database loads. For very large collections (>100k objects), monitor memory usage
              #   and consider processing in chunks or using a streaming approach if memory
              #   constraints are encountered. The batch_size parameter controls Redis I/O
              #   batching but does not affect memory usage since all objects are cached.
              #
              define_method(:"rebuild_#{index_name}") do |batch_size: 100, &progress_block|
                # PHASE 1: Find the collection containing the indexed objects
                # Look for a participation relationship where indexed_class participates in this scope_class
                collection_name = nil

                # Check if indexed_class has participation to this scope_class
                if indexed_class.respond_to?(:participation_relationships)
                  participation = indexed_class.participation_relationships.find do |rel|
                    rel.target_class == self.class
                  end
                  collection_name = participation&.collection_name if participation
                end

                # Get the collection DataType if we found a participation relationship
                collection = collection_name ? send(collection_name) : nil

                if collection
                  # PHASE 2: Load objects once and cache them for both discovery and rebuilding
                  # This avoids duplicate load_multi calls (previous approach loaded twice)
                  progress_block&.call(phase: :loading, current: 0, total: collection.size)

                  field_values = Set.new
                  cached_objects = []
                  processed = 0

                  collection.members.each_slice(batch_size) do |identifiers|
                    # Load objects in batches - SINGLE LOAD for both phases
                    objects = indexed_class.load_multi(identifiers).compact
                    cached_objects.concat(objects)

                    objects.each do |obj|
                      value = obj.send(field)
                      # Only track non-nil, non-empty field values
                      field_values << value.to_s if value && !value.to_s.strip.empty?
                    end

                    processed += identifiers.size
                    progress_block&.call(phase: :loading, current: processed, total: collection.size)
                  end

                  # PHASE 3: Clear this scope instance's field-value-specific index sets.
                  # SCAN also finds orphaned sets left by field values no object holds any more.
                  # The identifier in the prefix (e.g. "company:c-*:dept_index:") is escaped,
                  # so a glob character in it cannot widen the match past that literal prefix.
                  # The keys PHASE 4 writes are checked first: add_to_* writes the bucket of
                  # every non-nil field value.
                  progress_block&.call(phase: :clearing, current: 0, total: field_values.size)

                  bucket_prefix = MultiIndexGenerators.bucket_key_prefix(self, index_name)
                  live_bucket_keys = cached_objects.filter_map { |obj| obj.send(field) }.uniq
                                                   .map { |value| send("#{index_name}_for", value).dbkey }.uniq
                  MultiIndexGenerators.clear_index_buckets(
                    dbclient, bucket_prefix, live_bucket_keys: live_bucket_keys, batch_size: batch_size
                  ) do |key, cleared|
                    progress_block&.call(phase: :clearing, current: cleared, total: field_values.size, key: key)
                  end

                  # PHASE 4: Rebuild index from cached objects (no reload needed)
                  progress_block&.call(phase: :rebuilding, current: 0, total: cached_objects.size)

                  processed = 0
                  cached_objects.each_slice(batch_size) do |objects|
                    transaction do |_tx|
                      objects.each do |obj|
                        # Use the generated add_to method to maintain consistency
                        # This ensures the same logic is used as during normal operation
                        obj.send(:"add_to_#{scope_class_config}_#{index_name}", self)
                      end
                    end

                    processed += objects.size
                    progress_block&.call(phase: :rebuilding, current: processed, total: cached_objects.size)
                  end

                  Familia.info "[Rebuild] Multi-index #{index_name} rebuilt: #{field_values.size} field values, #{processed} objects"

                  processed  # Return count of processed objects

                else
                  # No participation relationship found - warn and suggest alternative
                  Familia.warn <<~WARNING
                    [Rebuild] Cannot rebuild multi-index #{index_name}: no participation relationship found

                    Multi-index rebuild requires a participation relationship to find objects.
                    Add a participation relationship to #{indexed_class.name}:

                      class #{indexed_class.name} < Familia::Horreum
                        participates_in #{self.class.name}, :collection_name, score: :field
                      end

                    Then access the collection via: #{self.class.config_name}.collection_name
                  WARNING

                  nil
                end
              end
            end
          end

          # Generates mutation methods ON THE INDEXED CLASS (Employee):
          # - employee.add_to_company_dept_index(company)
          # - employee.remove_from_company_dept_index(company)
          # - employee.update_in_company_dept_index(company, old_dept)
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :department)
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :dept_index)
          def generate_mutation_methods_self(indexed_class, field, scope_class, index_name)
            scope_class_config = scope_class.config_name
            indexed_class.class_eval do
              method_name = :"add_to_#{scope_class_config}_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                # Before any write: an untrackable scope produces an index
                # entry that destroy! could never find again.
                _ensure_trackable_index_scope!(scope_instance)

                field_value = send(field)
                return unless field_value

                _ensure_persisted_before_index_write!(index_name, scope_instance)

                index_set = scope_instance.send("#{index_name}_for", field_value)
                index_set.add(identifier)

                # Per-value entry: add_to_* is add-only, so the object may now
                # occupy several buckets and each needs its own cleanup entry.
                _record_index_scope(scope_class_config, index_name, scope_instance, field_value,
                                    cardinality: :multi)
              end

              method_name = :"remove_from_#{scope_class_config}_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} method #{method_name}")

              # @param scope_instance [Object] the scope holding the index
              # @param field_value [Object, nil] the value bucket to remove
              #   from. Defaults to the object's current field value,
              #   preserving the public single-argument call. destroy! cleanup
              #   passes the value recorded at index time instead, since the
              #   current one may have changed (or be nil on an
              #   identifier-only instance).
              define_method(method_name) do |scope_instance, field_value = nil|
                return unless scope_instance

                field_value = send(field) if field_value.nil?
                return unless field_value

                index_set = scope_instance.send("#{index_name}_for", field_value)
                index_set.remove(identifier)

                # field_value is part of the multi entry key -- the bucket
                # just left is the entry to drop, not the membership as a
                # whole (other buckets may still hold this object).
                _unrecord_index_scope(scope_class_config, index_name, scope_instance, field_value,
                                      cardinality: :multi)
              end

              method_name = :"update_in_#{scope_class_config}_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance, old_field_value = nil|
                return unless scope_instance

                _ensure_trackable_index_scope!(scope_instance)

                new_field_value = send(field)

                _ensure_persisted_before_index_write!(index_name, scope_instance)

                # Use Familia's transaction method for atomicity with DataType abstraction
                scope_instance.transaction do |_tx|
                  # Remove from old index if provided - use helper method
                  if old_field_value
                    old_index_set = scope_instance.send("#{index_name}_for", old_field_value)
                    old_index_set.remove(identifier)
                  end

                  # Add to new index if present - use helper method
                  if new_field_value
                    new_index_set = scope_instance.send("#{index_name}_for", new_field_value)
                    new_index_set.add(identifier)
                  end
                end

                # Mirror the bucket moves above into the tracker: drop the
                # entry for the retracted bucket, add one for the new bucket.
                #
                # Synced outside the block above, which behaves differently
                # depending on the caller. Standalone, scope_instance.transaction
                # opens a MULTI on the SCOPE's connection -- a tracker write
                # inside it would go to the wrong connection, since the tracker
                # belongs to this object. The tradeoff is that standalone, the
                # tracker sync is NOT atomic with the index write. During save
                # the block is reentrant (it joins the caller's MULTI via
                # Fiber[:familia_transaction]) so both land in that one
                # transaction and the tradeoff does not apply.
                _sync_multi_index_scope(scope_class_config, index_name, scope_instance,
                                        old_field_value, new_field_value)
              end
            end
          end

          # =========================================================================
          # CLASS-LEVEL MULTI-INDEX GENERATORS
          # =========================================================================
          #
          # When within: :class is used, these generators create class-level methods
          # instead of instance-scoped methods.
          #
          # Example:
          #   multi_index :role, :role_index  # within: :class is default
          #
          # Generates on Customer (class methods):
          #   - Customer.role_index_for('admin')   -> UnsortedSet factory
          #   - Customer.find_all_by_role('admin') -> [Customer, ...]
          #   - Customer.sample_from_role('admin', 3) -> random sample
          #   - Customer.rebuild_role_index          -> rebuild index
          #
          # Generates on Customer (instance methods, auto-called on save):
          #   - customer.add_to_class_role_index
          #   - customer.remove_from_class_role_index
          #   - customer.update_in_class_role_index(old_value)

          # Generates class-level factory method:
          # - Customer.role_index_for(field_value) -> UnsortedSet
          #
          # The factory validates field values for data quality. Glob pattern
          # characters (*, ?, [, ]) in field values are allowed but trigger
          # warnings since they can be confusing during debugging.
          #
          # @param indexed_class [Class] The class being indexed (e.g., Customer)
          # @param index_name [Symbol] Name of the index (e.g., :role_index)
          def generate_factory_method_class(indexed_class, index_name)
            # Capture index_name for use in validation context
            idx_name = index_name
            indexed_class.define_singleton_method(:"#{index_name}_for") do |field_value|
              # Validate field value and use the validated string for consistent key format.
              # Validation returns nil for nil/empty values, string otherwise.
              # We allow nil through (creates a "null" index key) but use the validated
              # string to ensure consistent type handling in key construction.
              validated = MultiIndexGenerators.validate_field_value(field_value, context: "#{name}.#{idx_name}")
              index_key = Familia.join(index_name, validated)
              Familia::UnsortedSet.new(index_key, parent: self, class: indexed_class, reference: true)
            end
          end

          # Generates class-level query methods:
          # - Customer.find_all_by_role(value) -> [Customer, ...]
          # - Customer.sample_from_role(value, count) -> random sample
          # - Customer.rebuild_role_index -> rebuild index
          #
          # @param indexed_class [Class] The class being indexed (e.g., Customer)
          # @param field [Symbol] The field to index (e.g., :role)
          # @param index_name [Symbol] Name of the index (e.g., :role_index)
          def generate_query_methods_class(indexed_class, field, index_name)
            # find_all_by_role(value)
            # Uses load_multi for efficient batch loading (avoids N+1 queries)
            indexed_class.define_singleton_method(:"find_all_by_#{field}") do |field_value|
              index_set = send("#{index_name}_for", field_value)
              identifiers = index_set.members
              load_multi(identifiers).compact
            end

            # sample_from_role(value, count)
            # Uses load_multi for efficient batch loading (avoids N+1 queries)
            indexed_class.define_singleton_method(:"sample_from_#{field}") do |field_value, count = 1|
              return [] if field_value.nil? || field_value.to_s.strip.empty?

              index_set = send("#{index_name}_for", field_value)
              identifiers = index_set.sample(count)
              load_multi(identifiers).compact
            end

            # rebuild_role_index(batch_size:, &progress)
            #
            # For class-level indexes, we iterate all instances of the class.
            # The phases match the instance-scoped rebuild: load every object
            # and its field value, check every bucket key the rebuild will
            # write, delete the class's bucket sets under the escaped bucket
            # prefix (e.g. "customer:role_index:"), then add each object to
            # the bucket of its field value.
            #
            # @param batch_size [Integer] Number of identifiers to process per batch
            # @yield [progress] Optional block called with progress updates; the
            #   phases are :discovering, :loading, :clearing and :rebuilding
            # @return [Integer] Number of objects processed, or 0 when the class
            #   has no instances collection
            # @raise [Familia::IndexBucketConflictError] if a bucket key the rebuild
            #   will write holds a type other than set. The rebuild raises before it
            #   deletes or writes anything. The error's #conflicts maps each such key
            #   to its type. The rebuild can run once each of those keys holds a set
            #   or no longer exists.
            indexed_class.define_singleton_method(:"rebuild_#{index_name}") do |batch_size: 100, &progress_block|
              # PHASE 1: Discover all field values and collect objects
              progress_block&.call(phase: :discovering, current: 0, total: 0)

              # Use class-level instances collection if available
              unless respond_to?(:instances) && instances.respond_to?(:members)
                Familia.warn "[Rebuild] Cannot rebuild class-level multi-index #{index_name}: " \
                             "no instances collection found. " \
                             "Ensure #{name} has class_sorted_set :instances or similar."
                return 0  # Return 0 for consistency - always return integer count
              end

              field_values = Set.new
              cached_objects = []
              processed = 0
              total_count = instances.size

              progress_block&.call(phase: :loading, current: 0, total: total_count)

              instances.members.each_slice(batch_size) do |identifiers|
                objects = load_multi(identifiers).compact
                cached_objects.concat(objects)

                objects.each do |obj|
                  value = obj.send(field)
                  field_values << value.to_s if value && !value.to_s.strip.empty?
                end

                processed += identifiers.size
                progress_block&.call(phase: :loading, current: processed, total: total_count)
              end

              # PHASE 2: Clear existing index sets (e.g. "customer:role_index:*") using SCAN.
              # The class prefix and delimiter are escaped like any other literal part.
              # The keys PHASE 3 writes, one per field value, are checked first.
              progress_block&.call(phase: :clearing, current: 0, total: field_values.size)

              bucket_prefix = MultiIndexGenerators.bucket_key_prefix(self, index_name)
              live_bucket_keys = field_values.map { |value| send("#{index_name}_for", value).dbkey }
              MultiIndexGenerators.clear_index_buckets(
                dbclient, bucket_prefix, live_bucket_keys: live_bucket_keys, batch_size: batch_size
              ) do |key, cleared|
                progress_block&.call(phase: :clearing, current: cleared, total: field_values.size, key: key)
              end

              # PHASE 3: Rebuild from cached objects
              progress_block&.call(phase: :rebuilding, current: 0, total: cached_objects.size)

              processed = 0
              cached_objects.each_slice(batch_size) do |objects|
                dbclient.multi do |conn|
                  objects.each do |obj|
                    field_value = obj.send(field)
                    next unless field_value && !field_value.to_s.strip.empty?

                    index_set = send("#{index_name}_for", field_value)
                    conn.sadd(index_set.dbkey, index_set.serialize_value(obj.identifier))
                  end
                end

                processed += objects.size
                progress_block&.call(phase: :rebuilding, current: processed, total: cached_objects.size)
              end

              Familia.info "[Rebuild] Class-level multi-index #{index_name} rebuilt: " \
                           "#{field_values.size} field values, #{processed} objects"

              processed
            end
          end

          # Generates instance mutation methods for class-level indexes:
          # - customer.add_to_class_role_index
          # - customer.remove_from_class_role_index
          # - customer.update_in_class_role_index(old_value)
          #
          # These are auto-called on save/destroy when auto-indexing is enabled.
          #
          # @param indexed_class [Class] The class being indexed (e.g., Customer)
          # @param field [Symbol] The field to index (e.g., :role)
          # @param index_name [Symbol] Name of the index (e.g., :role_index)
          def generate_mutation_methods_class(indexed_class, field, index_name)
            indexed_class.class_eval do
              method_name = :"add_to_class_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} class method #{method_name}")

              define_method(method_name) do
                field_value = send(field)
                return unless field_value && !field_value.to_s.strip.empty?

                _ensure_persisted_before_index_write!(index_name)

                index_set = self.class.send("#{index_name}_for", field_value)
                index_set.add(identifier)
              end

              method_name = :"remove_from_class_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} class method #{method_name}")

              define_method(method_name) do
                field_value = send(field)
                return unless field_value && !field_value.to_s.strip.empty?

                index_set = self.class.send("#{index_name}_for", field_value)
                index_set.remove(identifier)
              end

              method_name = :"update_in_class_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} class method #{method_name}")

              define_method(method_name) do |old_field_value|
                return unless old_field_value

                new_field_value = send(field)
                return if old_field_value == new_field_value

                _ensure_persisted_before_index_write!(index_name)

                # Get the index sets for old and new values
                old_set = self.class.send("#{index_name}_for", old_field_value)

                # Use DataType's serialize_value for consistency with add/remove methods.
                # This ensures the same serialization path is used across all index operations.
                serialized_id = old_set.serialize_value(identifier)

                # Use transaction for atomic remove + add to prevent data inconsistency
                transaction do |conn|
                  # Remove from old index
                  conn.srem(old_set.dbkey, serialized_id)

                  # Add to new index if present
                  if new_field_value && !new_field_value.to_s.strip.empty?
                    new_set = self.class.send("#{index_name}_for", new_field_value)
                    conn.sadd(new_set.dbkey, serialized_id)
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
