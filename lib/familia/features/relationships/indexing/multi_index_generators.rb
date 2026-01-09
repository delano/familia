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

          # Validates a field value for use in index key construction.
          # This is primarily for data quality and debugging clarity, not security.
          #
          # Security note: Redis SCAN patterns use the namespace prefix (e.g.,
          # "customer:role_index:") which is derived from class/index metadata,
          # not user input. Glob characters in stored field values are treated
          # as literal characters in key names, not as pattern wildcards.
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
              generate_factory_method(scope_class, index_name)
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
          def generate_factory_method(scope_class, index_name)
            actual_scope_class = Familia.resolve_class(scope_class)

            actual_scope_class.class_eval do
              # Helper method to get index set for a specific field value
              # This acts as a factory for field-value-specific DataTypes
              define_method(:"#{index_name}_for") do |field_value|
                # Return properly managed DataType instance with parameterized key
                index_key = Familia.join(index_name, field_value)
                Familia::UnsortedSet.new(index_key, parent: self)
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
              # Multi-indexes create separate sets for each field value, requiring a three-phase approach:
              # 1. Loading: Load all objects once and cache them (discovers field values simultaneously)
              # 2. Clearing: Remove all existing index sets using SCAN
              # 3. Rebuilding: Rebuild index from cached objects (no reload needed)
              #
              # @param batch_size [Integer] Number of identifiers to process per batch
              # @yield [progress] Optional block called with progress updates
              # @yieldparam progress [Hash] Progress information with keys:
              #   - :phase [Symbol] Current phase (:loading, :clearing, :rebuilding)
              #   - :current [Integer] Current item count
              #   - :total [Integer] Total items (when known)
              #   - :field_value [String] Current field value being processed
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

                  # PHASE 3: Clear all existing field-value-specific index sets
                  # Use SCAN to find all existing index keys (including orphaned ones from deleted field values)
                  progress_block&.call(phase: :clearing, current: 0, total: field_values.size)

                  # Get the base pattern for this index by creating a sample index set
                  # The "*" creates a wildcard pattern like "company:123:dept_index:*" for SCAN
                  sample_index = send(:"#{index_name}_for", "*")
                  index_pattern = sample_index.dbkey

                  # Find all existing index keys using SCAN
                  cleared_count = 0
                  dbclient.scan_each(match: index_pattern) do |key|
                    dbclient.del(key)
                    cleared_count += 1
                    progress_block&.call(phase: :clearing, current: cleared_count, total: field_values.size, key: key)
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

                field_value = send(field)
                return unless field_value

                # Use helper method on scope instance instead of manual instantiation
                index_set = scope_instance.send("#{index_name}_for", field_value)

                # Use UnsortedSet DataType method (no scoring)
                index_set.add(identifier)
              end

              method_name = :"remove_from_#{scope_class_config}_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                field_value = send(field)
                return unless field_value

                # Use helper method on scope instance instead of manual instantiation
                index_set = scope_instance.send("#{index_name}_for", field_value)

                # Remove using UnsortedSet DataType method
                index_set.remove(identifier)
              end

              method_name = :"update_in_#{scope_class_config}_#{index_name}"
              Familia.debug("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance, old_field_value = nil|
                return unless scope_instance

                new_field_value = send(field)

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
              Familia::UnsortedSet.new(index_key, parent: self)
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
            # For class-level indexes, we iterate all instances of the class
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

              # PHASE 2: Clear existing index sets using SCAN
              progress_block&.call(phase: :clearing, current: 0, total: field_values.size)

              # Get pattern for all index keys: "customer:role_index:*"
              #
              # Security note: The SCAN pattern is safe because:
              # 1. The namespace prefix (e.g., "customer:role_index:") is derived from
              #    class metadata and index name, not user input
              # 2. The "*" wildcard only matches keys within this namespace
              # 3. Glob characters stored IN field values (e.g., a role named "admin*")
              #    are literal characters in the key name, not SCAN wildcards
              # 4. SCAN cannot match keys outside the namespace prefix
              sample_index = send(:"#{index_name}_for", "*")
              index_pattern = sample_index.dbkey

              cleared_count = 0
              dbclient.scan_each(match: index_pattern) do |key|
                dbclient.del(key)
                cleared_count += 1
                progress_block&.call(phase: :clearing, current: cleared_count, total: field_values.size, key: key)
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
                    # Use JsonSerializer for consistent serialization with update method
                    serialized_id = Familia::JsonSerializer.dump(obj.identifier)
                    conn.sadd(index_set.dbkey, serialized_id)
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

                # Get the index sets for old and new values
                old_set = self.class.send("#{index_name}_for", old_field_value)

                # Serialize identifier for consistent storage (JSON encoded)
                serialized_id = Familia::JsonSerializer.dump(identifier)

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
