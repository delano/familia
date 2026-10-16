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
          # A blank value (nil, empty or whitespace only) is the exception.
          # Validation turns it into nil, which Familia.join drops, so the
          # factories name its key "<owner key>:<index_name>" with no
          # trailing delimiter. That key is not exclusive to the index: it
          # is also the key of a related field of +owner+ with the same name
          # as the index, such as a scope class's `set :tags` beside
          # `multi_index :tag, :tags, within: Scope`, or `class_set :roles`
          # beside `multi_index :role, :roles`. So the multi_index methods
          # of +owner+ do not read or write it: add_to_*, update_in_*,
          # remove_from_* and the rebuild skip blank values, find_all_by_*
          # and sample_from_* return [] for them, IndexDescriptor#each_record
          # raises for them, and the rebuild SCAN of +owner+ does not match
          # the key (see .blank_field_value?).
          #
          # The key can still be the bucket of a shorter scope. When +owner+
          # is a scope whose identifier is "<other id>:<index_name>:<value>",
          # the key is also the bucket of "<value>:<index_name>" in scope
          # "<other id>": audit_multi_indexes reads it as that bucket, and
          # the rebuild of that scope deletes or rewrites it. This does not
          # happen when the scope class declares a set field named
          # +index_name+ and +owner+ exists, because the key is then a key
          # of +owner+ (see RecordKeyOwnership.other_record_key).
          #
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param index_name [Symbol] name of the index
          # @return [String]
          def bucket_key_prefix(owner, index_name)
            Familia::UnsortedSet.new(Familia.join(index_name, ''), parent: owner).dbkey
          end

          # Whether +field_value+ is blank: nil, or empty or whitespace only
          # as a String. A multi_index does not index a blank value, and the
          # generated methods of an owner do not read or write the key the
          # factories name for one on that owner (see .bucket_key_prefix).
          #
          # @param field_value [Object]
          # @return [Boolean]
          def blank_field_value?(field_value)
            field_value.nil? || field_value.to_s.strip.empty?
          end

          # Yields the keys of the per-value bucket sets of +index_name+ on
          # +owner+, in slices of up to +batch_size+ keys.
          #
          # The SCAN pattern is "<bucket prefix>*", for example
          # "company:c-1:dept_index:*" or "customer:role_index:*". The
          # bucket prefix from .bucket_key_prefix is escaped with
          # Familia.escape_glob before the SCAN wildcard is appended, so glob
          # characters in a scope identifier, the class prefix or the
          # delimiter cannot make the pattern match keys outside that
          # literal prefix. SCAN's TYPE option leaves out every key that
          # does not hold a set, the type the factories give each bucket.
          # The Valkey and Redis SCAN command histories both list "Added the
          # `TYPE` subcommand." under 6.0.0, and README.md lists the
          # prerequisite "**Valkey/Redis**: 6.0+". Each returned key must
          # also start with the literal prefix (see .select_index_buckets).
          #
          # A key can start with the literal prefix and still be another
          # record's key, because an identifier may contain the delimiter.
          # "company:c-1:dept_index:x:dept_index:ops" is both the bucket of
          # value "x:dept_index:ops" in scope "c-1" and the "ops" bucket of
          # scope "c-1:dept_index:x". Keys that
          # RecordKeyOwnership.other_record_key assigns to an existing record
          # with a longer identifier are yielded in +others+, not in
          # +buckets+, so the rebuild does not delete them and the
          # class-level audit does not read them. So is a key with more
          # candidate owners than RecordKeyOwnership::MAX_CANDIDATE_SPLITS,
          # whose owner is not checked. The candidates of the keys in a
          # slice are checked in pipelines of at most
          # RecordKeyOwnership::MAX_CANDIDATE_BATCH_BYTES of identifiers.
          #
          # The key "<owner key>:<index_name>", which the factories name for
          # a blank value, does not match the pattern and is not yielded
          # (see .bucket_key_prefix).
          #
          # @param client [Redis] connection that owns the buckets
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param index_name [Symbol] name of the index
          # @param batch_size [Integer] SCAN count hint and slice size
          # @yieldparam buckets [Array<String>] bucket keys of the slice,
          #   possibly empty
          # @yieldparam others [Hash{String => String, Symbol}] the other
          #   keys of the slice, each mapped to the hash key of the record
          #   that owns it or to RecordKeyOwnership::TOO_MANY_CANDIDATES
          # @return [Enumerator, nil] an Enumerator when no block is given
          def each_index_bucket_slice(client, owner, index_name, batch_size: 100)
            return enum_for(__method__, client, owner, index_name, batch_size: batch_size) unless block_given?

            bucket_prefix = bucket_key_prefix(owner, index_name)
            names = RecordKeyOwnership.record_set_key_names(owner)
            pattern = "#{Familia.escape_glob(bucket_prefix)}*"
            client.scan_each(match: pattern, count: batch_size, type: BUCKET_KEY_TYPE)
                  .each_slice(batch_size) do |keys|
              candidates = select_index_buckets(keys, bucket_prefix)
              next if candidates.empty?

              owners = RecordKeyOwnership.other_record_key_owners(candidates, owner, names: names)
              buckets = []
              others = {}
              candidates.zip(owners) do |key, record_key|
                record_key ? others[key] = record_key : buckets << key
              end
              yield buckets, others
            end
            nil
          end

          # Deletes the per-value bucket sets of +index_name+ on +owner+,
          # including buckets for field values that no object holds any
          # more.
          #
          # +live_bucket_keys+ are the keys the rebuild writes after this
          # returns. They are checked with .check_live_bucket_keys! first.
          # Then every bucket under the prefix is found before any is
          # deleted, and a key whose owner was not checked (see
          # .each_index_bucket_slice) raises as well. So a key the rebuild
          # could not write, or could not tell from another record's key,
          # stops it before any key is deleted.
          #
          # Only the bucket keys .each_index_bucket_slice yields are deleted.
          # A key under the prefix that holds another type is left alone,
          # and so is a set that is another existing record's key. Each key
          # gets its own DEL in one pipeline per batch, so a key that was
          # already gone when its DEL ran is neither yielded nor counted.
          #
          # @param client [Redis] connection that owns the buckets
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param index_name [Symbol] name of the index
          # @param live_bucket_keys [Array<String>] keys the rebuild writes next
          # @param batch_size [Integer] SCAN count hint, DEL and TYPE batch size
          # @yieldparam key [String] a bucket key that DEL removed
          # @yieldparam cleared [Integer] buckets deleted so far
          # @return [Integer] number of bucket keys DEL removed
          # @raise [Familia::IndexBucketConflictError] see .check_live_bucket_keys!,
          #   and for a key under the prefix whose owner was not checked
          def clear_index_buckets(client, owner, index_name, live_bucket_keys:, batch_size: 100, &on_delete)
            check_live_bucket_keys!(client, owner, live_bucket_keys, batch_size: batch_size)

            stale = []
            unchecked = {}
            each_index_bucket_slice(client, owner, index_name, batch_size: batch_size) do |buckets, others|
              stale.concat(buckets)
              others.each do |key, record_key|
                unchecked[key] = record_key if record_key == RecordKeyOwnership::TOO_MANY_CANDIDATES
              end
            end
            raise Familia::IndexBucketConflictError, unchecked unless unchecked.empty?

            cleared = 0
            stale.each_slice(batch_size) do |buckets|
              deleted = client.pipelined do |pipe|
                buckets.each { |key| pipe.del(key) }
              end
              buckets.zip(deleted) do |key, count|
                next unless count.to_i.positive?

                cleared += 1
                on_delete&.call(key, cleared)
              end
            end

            cleared
          end

          # Raises Familia::IndexBucketConflictError when one of
          # +bucket_keys+ holds a type other than a set, is another
          # existing record's key (see RecordKeyOwnership.other_record_key_owner)
          # or has more candidate owners than the rebuild checks.
          #
          # After the clearing phase, the rebuild adds every object to the
          # bucket of its field value. A key of another type there is not a
          # bucket and may be another record's data, such as the list of a
          # record named after a class-level index when a live field value
          # equals that list's name. SADD into it raises WRONGTYPE, which
          # would stop the rebuild after clearing had already emptied the
          # other buckets, and deleting it could destroy that data. A set
          # that is another record's key would receive index members. So
          # the rebuild checks every key it will write before it deletes any.
          #
          # @param client [Redis] connection that owns the buckets
          # @param owner [Familia::Horreum, Class] the scope instance, or the
          #   indexed class for a class-level index
          # @param bucket_keys [Array<String>] keys the rebuild will write
          # @param batch_size [Integer] number of keys checked per pipeline
          # @return [nil]
          # @raise [Familia::IndexBucketConflictError] naming each such key,
          #   its type or RecordKeyOwnership::TOO_MANY_CANDIDATES and, for
          #   another record's key, that record's hash key
          def check_live_bucket_keys!(client, owner, bucket_keys, batch_size: 100)
            conflicts = {}
            owners = {}
            names = RecordKeyOwnership.record_set_key_names(owner)

            bucket_keys.each_slice(batch_size) do |keys|
              types = client.pipelined do |pipe|
                keys.each { |key| pipe.type(key) }
              end
              record_keys = RecordKeyOwnership.other_record_key_owners(keys, owner, names: names)
              keys.each_with_index do |key, idx|
                type = types[idx]
                record_key = record_keys[idx]
                if record_key == RecordKeyOwnership::TOO_MANY_CANDIDATES
                  conflicts[key] = record_key
                  next
                end

                owners[key] = record_key if record_key
                conflicts[key] = type if record_key || !WRITABLE_BUCKET_KEY_TYPES.include?(type)
              end
            end
            raise Familia::IndexBucketConflictError.new(conflicts, owners) unless conflicts.empty?

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
                # A blank value is not indexed (see MultiIndexGenerators.bucket_key_prefix)
                return [] if MultiIndexGenerators.blank_field_value?(field_value)

                index_set = send("#{index_name}_for", field_value) # i.e. UnsortedSet

                # Get random members efficiently (O(1) via SRANDMEMBER with count)
                # Returns array even for count=1 for consistent API
                index_set.sample(count).map do |id|
                  indexed_class.find_by_identifier(id)
                end
              end

              # Generate bulk query method (e.g., company.find_all_by_department)
              define_method(:"find_all_by_#{field}") do |field_value|
                # A blank value is not indexed (see MultiIndexGenerators.bucket_key_prefix)
                return [] if MultiIndexGenerators.blank_field_value?(field_value)

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
              #    that start with that literal prefix and hold a set are deleted. A set that
              #    also belongs to an existing scope record with a longer identifier is left
              #    alone (see RecordKeyOwnership.other_record_key). The SCAN pattern is the
              #    escaped prefix followed by "*", e.g. "company:c-1:dept_index:*", so the key
              #    "company:c-1:dept_index" that the factory names for a blank value is not
              #    touched: it may be a related field of the same name on this scope class.
              # 3. Rebuilding: Add each cached object to the bucket of its field value
              #    (no reload needed). An object with a blank field value is not indexed.
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
              #   write holds a type other than set or is another existing record's key, or if
              #   a key it will write or delete has more candidate owner records than
              #   RecordKeyOwnership::MAX_CANDIDATE_SPLITS. The rebuild raises before it
              #   deletes or writes anything. The error's #conflicts maps each such key to its
              #   type or to RecordKeyOwnership::TOO_MANY_CANDIDATES, and #owners maps each
              #   key of another record to that record's hash key.
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
                  # every non-blank field value.
                  progress_block&.call(phase: :clearing, current: 0, total: field_values.size)

                  live_bucket_keys = field_values.map { |value| send("#{index_name}_for", value).dbkey }
                  MultiIndexGenerators.clear_index_buckets(
                    dbclient, self, index_name, live_bucket_keys: live_bucket_keys, batch_size: batch_size
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

                # A blank value is not indexed, as in the class-level index:
                # its key "<scope key>:<index>" may be a related field of the
                # scope (see MultiIndexGenerators.bucket_key_prefix). Its
                # tracker entry below is still recorded, so save keeps
                # refreshing this membership once the value is no longer
                # blank.
                unless MultiIndexGenerators.blank_field_value?(field_value)
                  index_set = scope_instance.send("#{index_name}_for", field_value)
                  index_set.add(identifier)
                end

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

                # A blank value has no bucket (see add_to_*), so only its
                # tracker entry is dropped.
                unless MultiIndexGenerators.blank_field_value?(field_value)
                  index_set = scope_instance.send("#{index_name}_for", field_value)
                  index_set.remove(identifier)
                end

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
                # A blank value is not indexed, as in the class-level index,
                # but the tracker below still records it (see add_to_*).
                # Neither a blank old value nor a blank new value touches
                # the key "<scope key>:<index>", which may be a related field
                # of the scope (see MultiIndexGenerators.bucket_key_prefix).
                index_value = new_field_value unless MultiIndexGenerators.blank_field_value?(new_field_value)
                retract_value = old_field_value unless MultiIndexGenerators.blank_field_value?(old_field_value)

                _ensure_persisted_before_index_write!(index_name, scope_instance)

                # Use Familia's transaction method for atomicity with DataType abstraction
                scope_instance.transaction do |_tx|
                  # Remove from old index if provided - use helper method
                  if retract_value
                    old_index_set = scope_instance.send("#{index_name}_for", retract_value)
                    old_index_set.remove(identifier)
                  end

                  # Add to new index if present - use helper method
                  if index_value
                    new_index_set = scope_instance.send("#{index_name}_for", index_value)
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
              # A blank value is not indexed (see MultiIndexGenerators.bucket_key_prefix)
              return [] if MultiIndexGenerators.blank_field_value?(field_value)

              index_set = send("#{index_name}_for", field_value)
              identifiers = index_set.members
              load_multi(identifiers).compact
            end

            # sample_from_role(value, count)
            # Uses load_multi for efficient batch loading (avoids N+1 queries)
            indexed_class.define_singleton_method(:"sample_from_#{field}") do |field_value, count = 1|
              return [] if MultiIndexGenerators.blank_field_value?(field_value)

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
            # prefix (e.g. SCAN "customer:role_index:*"), then add each
            # object with a non-blank field value to the bucket of that
            # value. The key "customer:role_index" that the factory names for
            # a blank value is not matched or touched: it may be a
            # class-level related field of the same name. A set under
            # the prefix that is a set field of an existing record whose
            # identifier starts with the index name is left alone (see
            # RecordKeyOwnership.other_record_key).
            #
            # @param batch_size [Integer] Number of identifiers to process per batch
            # @yield [progress] Optional block called with progress updates; the
            #   phases are :discovering, :loading, :clearing and :rebuilding
            # @return [Integer] Number of objects processed, or 0 when the class
            #   has no instances collection
            # @raise [Familia::IndexBucketConflictError] if a bucket key the rebuild
            #   will write holds a type other than set or is another existing record's
            #   key, or if a key it will write or delete has more candidate owner
            #   records than RecordKeyOwnership::MAX_CANDIDATE_SPLITS. The rebuild
            #   raises before it deletes or writes anything. The error's #conflicts
            #   maps each such key to its type or to
            #   RecordKeyOwnership::TOO_MANY_CANDIDATES, and #owners maps each key of
            #   another record to that record's hash key.
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

              live_bucket_keys = field_values.map { |value| send("#{index_name}_for", value).dbkey }
              MultiIndexGenerators.clear_index_buckets(
                dbclient, self, index_name, live_bucket_keys: live_bucket_keys, batch_size: batch_size
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
                  # Remove from old index. A blank old value has no bucket:
                  # its key may be a class-level related field of the same
                  # name (see MultiIndexGenerators.bucket_key_prefix).
                  unless MultiIndexGenerators.blank_field_value?(old_field_value)
                    conn.srem(old_set.dbkey, serialized_id)
                  end

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
