# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      module Indexing
        # Generators for unique index (1:1) methods
        #
        # Unique indexes use HashKey DataType for field-to-object identifier mapping.
        # Each field value maps to exactly one object identifier.
        #
        # Example (instance-scoped):
        #   unique_index :badge_number, :badge_index, within: Company
        #
        # Generates on Company (destination):
        #   - company.find_by_badge_number(badge)
        #   - company.find_all_by_badge_number([badges])
        #   - company.badge_index
        #   - company.rebuild_badge_index
        #
        # Generates on Employee (self):
        #   - employee.add_to_company_badge_index(company)
        #   - employee.remove_from_company_badge_index(company)
        #   - employee.update_in_company_badge_index(company, old_badge)
        #
        # Example (class-level):
        #   unique_index :email, :email_index
        #
        # Generates on Employee (class):
        #   - Employee.find_by_email(email)
        #   - Employee.find_all_by_email([emails])
        #   - Employee.email_index
        #   - Employee.rebuild_email_index
        #
        # Generates on Employee (self):
        #   - employee.add_to_class_email_index
        #   - employee.remove_from_class_email_index
        #   - employee.update_in_class_email_index(old_email)
        module UniqueIndexGenerators
          module_function

          # Generates query methods ON THE PARENT CLASS (Company when within: Company):
          # - company.find_by_badge_number(badge) - find by field value
          # - company.find_all_by_badge_number([badges]) - batch lookup
          # - company.badge_index - DataType accessor
          # - company.rebuild_badge_index - rebuild index
          def generate_query_methods_destination(target_class, field, index_name, indexed_class)
            # Resolve target class using Familia pattern
            actual_target_class = Familia.resolve_class(target_class)

            # Generate instance finder method (e.g., company.find_by_badge_number)
            actual_target_class.class_eval do
              define_method("find_by_#{field}") do |field_value|
                # Create HashKey DataType for this parent instance
                index_hash = Familia::HashKey.new(index_name, parent: self)

                # Get the identifier from the hash
                object_id = index_hash[field_value.to_s]
                return nil unless object_id

                indexed_class.new(object_id)
              end

              # Generate bulk finder method (e.g., company.find_all_by_badge_number)
              define_method("find_all_by_#{field}") do |field_values|
                return [] if field_values.empty?

                # Create HashKey DataType for this parent instance
                index_hash = Familia::HashKey.new(index_name, parent: self)

                # Get all identifiers from the hash
                object_ids = index_hash.values_at(*field_values.map(&:to_s))
                # Filter out nil values and instantiate objects
                object_ids.compact.map { |object_id| indexed_class.new(object_id) }
              end

              # Generate method to get the index HashKey for this parent instance
              define_method(index_name) do
                # Return properly managed DataType instance
                Familia::HashKey.new(index_name, parent: self)
              end

              # Generate method to rebuild the unique index for this parent instance
              define_method("rebuild_#{index_name}") do
                index_hash = Familia::HashKey.new(index_name, parent: self)

                # Clear existing index using DataType method
                index_hash.clear

                # Rebuild from all existing objects
                # This would need to scan through all objects belonging to this parent
                # Implementation depends on how objects are stored/tracked
              end
            end
          end

          # Generates mutation methods ON THE INDEXED CLASS (Employee):
          # Instance methods for parent-scoped unique index operations:
          # - employee.add_to_company_badge_index(company)
          # - employee.remove_from_company_badge_index(company)
          # - employee.update_in_company_badge_index(company, old_badge)
          def generate_mutation_methods_self(target_class, field, index_name, indexed_class)
            target_class_config = target_class.config_name
            indexed_class.class_eval do
              method_name = "add_to_#{target_class_config}_#{index_name}"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |target_instance|
                return unless target_instance

                field_value = send(field)
                return unless field_value

                # Create HashKey DataType for this parent instance
                index_hash = Familia::HashKey.new(index_name, parent: target_instance)

                # Use HashKey DataType method
                index_hash[field_value.to_s] = identifier
              end

              method_name = "remove_from_#{target_class_config}_#{index_name}"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |target_instance|
                return unless target_instance

                field_value = send(field)
                return unless field_value

                # Create HashKey DataType for this parent instance
                index_hash = Familia::HashKey.new(index_name, parent: target_instance)

                # Remove using HashKey DataType method
                index_hash.remove(field_value.to_s)
              end

              method_name = "update_in_#{target_class_config}_#{index_name}"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |target_instance, old_field_value = nil|
                return unless target_instance

                new_field_value = send(field)

                # Use Familia's transaction method for atomicity with DataType abstraction
                target_instance.transaction do |_tx|
                  # Create HashKey DataType for this parent instance
                  index_hash = Familia::HashKey.new(index_name, parent: target_instance)

                  # Remove old value if provided
                  index_hash.remove(old_field_value.to_s) if old_field_value

                  # Add new value if present
                  index_hash[new_field_value.to_s] = identifier if new_field_value
                end
              end
            end
          end

          # Generates query methods ON THE INDEXED CLASS (Employee):
          # Class-level methods (singleton):
          # - Employee.find_by_email(email)
          # - Employee.find_all_by_email([emails])
          # - Employee.email_index
          # - Employee.rebuild_email_index
          def generate_query_methods_class(field, index_name, indexed_class)
            indexed_class.define_singleton_method("find_by_#{field}") do |field_value|
              index_hash = send(index_name) # Access the class-level hashkey DataType
              object_id = index_hash[field_value.to_s]

              return nil unless object_id

              new(object_id)
            end

            # Generate class-level bulk finder method
            indexed_class.define_singleton_method("find_all_by_#{field}") do |field_values|
              return [] if field_values.empty?

              index_hash = send(index_name) # Access the class-level hashkey DataType
              object_ids = index_hash.values_at(*field_values.map(&:to_s))
              # Filter out nil values and instantiate objects
              object_ids.compact.map { |object_id| new(object_id) }
            end

            # The index accessor method is already created by the class_hashkey declaration
            # No need to manually create it - Horreum handles this automatically

            # Generate method to rebuild the class-level index
            indexed_class.define_singleton_method("rebuild_#{index_name}") do
              index_hash = send(index_name) # Access the class-level hashkey DataType

              # Clear existing index using DataType method
              index_hash.clear

              # Rebuild from all existing objects
              # This would need to scan through all objects of this class
              # Implementation depends on how objects are stored/tracked
            end
          end

          # Generates mutation methods ON THE INDEXED CLASS (Employee):
          # Instance methods for class-level index operations:
          # - employee.add_to_class_email_index
          # - employee.remove_from_class_email_index
          # - employee.update_in_class_email_index(old_email)
          def generate_mutation_methods_class(field, index_name, indexed_class)
            indexed_class.class_eval do
              define_method("add_to_class_#{index_name}") do
                index_hash = self.class.send(index_name)  # Access the class-level hashkey DataType
                field_value = send(field)

                return unless field_value

                index_hash[field_value.to_s] = identifier
              end

              define_method("remove_from_class_#{index_name}") do
                index_hash = self.class.send(index_name)  # Access the class-level hashkey DataType
                field_value = send(field)

                return unless field_value

                index_hash.remove(field_value.to_s)
              end

              define_method("update_in_class_#{index_name}") do |old_field_value = nil|
                new_field_value = send(field)

                # Use class-level transaction for atomicity with DataType abstraction
                self.class.transaction do |_tx|
                  index_hash = self.class.send(index_name) # Access the class-level hashkey DataType

                  # Remove old value if provided
                  index_hash.remove(old_field_value.to_s) if old_field_value

                  # Add new value if present
                  index_hash[new_field_value.to_s] = identifier if new_field_value
                end
              end
            end
          end

          end
      end
    end
  end
end
