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

          # Generates query methods ON THE PARENT CLASS (Company when within: Company):
          # - company.sample_from_department(dept, count=1) - random sampling
          # - company.find_all_by_department(dept) - all objects
          # - company.dept_index_for(dept_value) - DataType accessor
          # - company.rebuild_dept_index - rebuild index
          def generate_query_methods_destination(target_class, field, index_name, indexed_class)
            # Resolve target class using Familia pattern
            actual_target_class = Familia.resolve_class(target_class)

            # Generate instance sampling method (e.g., company.sample_from_department)
            actual_target_class.class_eval do
              define_method("sample_from_#{field}") do |field_value, count = 1|
                # Create DataType for this specific field value index using proper Horreum pattern
                index_key = "#{index_name}:#{field_value}"
                index_set = Familia::UnsortedSet.new(index_key, parent: self)

                # Get random members efficiently (O(1) via SRANDMEMBER with count)
                # Returns array even for count=1 for consistent API
                members = index_set.dbclient.srandmember(index_set.dbkey, count) || []
                members.map { |id| indexed_class.new(index_set.deserialize_value(id)) }
              end

              # Generate bulk finder method (e.g., company.find_all_by_department)
              define_method("find_all_by_#{field}") do |field_value|
                # Create DataType for this specific field value index using proper Horreum pattern
                index_key = "#{index_name}:#{field_value}"
                index_set = Familia::UnsortedSet.new(index_key, parent: self)

                # Get all members from set
                members = index_set.members
                members.map { |id| indexed_class.new(id) }
              end

              # Generate method to get the index for a specific field value
              define_method("#{index_name}_for") do |field_value|
                # Return properly managed DataType instance
                index_key = "#{index_name}:#{field_value}"
                Familia::UnsortedSet.new(index_key, parent: self)
              end

              # Generate method to rebuild the index for this parent instance
              define_method("rebuild_#{index_name}") do
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
          def generate_mutation_methods_self(target_class, field, index_name, indexed_class)
            target_class_config = target_class.config_name
            indexed_class.class_eval do
              method_name = "add_to_#{target_class_config}_#{index_name}"
              Familia.ld("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |target_instance|
                return unless target_instance

                field_value = send(field)
                return unless field_value

                # Create DataType for this specific field value index using proper Horreum pattern
                index_key = "#{index_name}:#{field_value}"
                index_set = Familia::UnsortedSet.new(index_key, parent: target_instance)

                # Use UnsortedSet DataType method (no scoring)
                index_set.add(identifier)
              end

              method_name = "remove_from_#{target_class_config}_#{index_name}"
              Familia.ld("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |target_instance|
                return unless target_instance

                field_value = send(field)
                return unless field_value

                # Create DataType for this specific field value index using proper Horreum pattern
                index_key = "#{index_name}:#{field_value}"
                index_set = Familia::UnsortedSet.new(index_key, parent: target_instance)

                # Remove using UnsortedSet DataType method
                index_set.remove(identifier)
              end

              method_name = "update_in_#{target_class_config}_#{index_name}"
              Familia.ld("[MultiIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |target_instance, old_field_value = nil|
                return unless target_instance

                new_field_value = send(field)

                # Use Familia's transaction method for atomicity with DataType abstraction
                target_instance.transaction do |_tx|
                  # Remove from old index if provided
                  if old_field_value
                    old_index_key = "#{index_name}:#{old_field_value}"
                    old_index_set = Familia::UnsortedSet.new(old_index_key, parent: target_instance)
                    old_index_set.remove(identifier)
                  end

                  # Add to new index if present
                  if new_field_value
                    new_index_key = "#{index_name}:#{new_field_value}"
                    new_index_set = Familia::UnsortedSet.new(new_index_key, parent: target_instance)
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
