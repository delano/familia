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

              # Generate method to rebuild the index for this parent instance
              define_method(:"rebuild_#{index_name}") do
                # This would need to be implemented based on how you track which
                # objects belong to this parent instance
                # For now, just a placeholder
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
