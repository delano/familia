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

          # Main setup method that orchestrates multi-value index creation
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index
          # @param index_name [Symbol] Name of the index
          # @param within [Class, Symbol] Scope class for instance-scoped index (required)
          # @param query [Boolean] Whether to generate query methods
          def setup(indexed_class:, field:, index_name:, within:, query:)
            # Multi-index always requires a scope context
            scope_class = within
            resolved_class = Familia.resolve_class(scope_class)

            # Store metadata for this indexing relationship
            indexed_class.indexing_relationships << IndexingRelationship.new(
              field:             field,
              scope_class:       scope_class,
              within:            within,
              index_name:        index_name,
              query:            query,
              cardinality:       :multi,
            )

            # Always generate the factory method - required by mutation methods
            if scope_class.is_a?(Class)
              generate_factory_method(resolved_class, index_name)
            end

            # Generate query methods on the scope class (optional)
            if query && scope_class.is_a?(Class)
              generate_query_methods_destination(indexed_class, field, resolved_class, index_name)
            end

            # Generate mutation methods on the indexed class
            generate_mutation_methods_self(indexed_class, field, resolved_class, index_name)
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
                index_key = "#{index_name}:#{field_value}"
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
              # Multi-indexes create separate sets for each field value, requiring a two-phase approach:
              # 1. Discovery: Find all unique field values by loading objects
              # 2. Clear & Rebuild: Remove old index sets and rebuild from current objects
              #
              # @param batch_size [Integer] Number of identifiers to process per batch
              # @yield [progress] Optional block called with progress updates
              # @yieldparam progress [Hash] Progress information with keys:
              #   - :phase [Symbol] Current phase (:discovering, :clearing, :rebuilding)
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
              # @note This method requires loading all objects to discover field values.
              #   For large collections (>10k objects), consider using SCAN approach or
              #   maintaining a separate field-value index.
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
        end
      end
    end
  end
end
