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
        #   - employee.add_to_class_email_index (called automatically on save)
        #   - employee.remove_from_class_email_index
        #   - employee.update_in_class_email_index(old_email)
        #
        # Note: Class-level indexes auto-populate on save(). Instance-scoped indexes
        # (with within:) remain manual as they require parent context.
        module UniqueIndexGenerators
          module_function

          using Familia::Refinements::StylizeWords

          # Main setup method that orchestrates unique index creation
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index
          # @param index_name [Symbol] Name of the index
          # @param within [Class, Symbol, nil] Scope class for instance-scoped index
          # @param query [Boolean] Whether to generate query methods
          def setup(indexed_class:, field:, index_name:, within:, query:)
            # Normalize parameters and determine scope type
            scope_class, scope_type = if within
              k = Familia.resolve_class(within)
              [k, :instance]
            else
              [indexed_class, :class]
            end

            # Store metadata for this indexing relationship
            indexed_class.indexing_relationships << IndexingRelationship.new(
              field:             field,
              scope_class:       scope_class,
              within:            within,
              index_name:        index_name,
              query:             query,
              cardinality:       :unique,
            )

            # Generate appropriate methods based on scope type
            case scope_type
            when :instance
              # Instance-scoped index (within: Company)
              if query && scope_class.is_a?(Class)
                generate_query_methods_destination(indexed_class, field, scope_class, index_name)
              end
              generate_mutation_methods_self(indexed_class, field, scope_class, index_name)
            when :class
              # Class-level index (no within:)
              indexed_class.send(:ensure_index_field, indexed_class, index_name, :class_hashkey)
              generate_query_methods_class(field, index_name, indexed_class) if query
              generate_mutation_methods_class(field, index_name, indexed_class)
            end
          end

          # Generates query methods ON THE SCOPE CLASS (Company when within: Company)
          #
          # - company.find_by_badge_number(badge) - find by field value
          # - company.find_all_by_badge_number([badges]) - batch lookup
          # - company.badge_index - DataType accessor
          # - company.rebuild_badge_index - rebuild index
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :badge_number)
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :badge_index)
          def generate_query_methods_destination(indexed_class, field, scope_class, index_name)
            # Resolve scope class using Familia pattern
            actual_scope_class = Familia.resolve_class(scope_class)

            # Ensure the index field is declared (creates accessor that returns DataType)
            actual_scope_class.send(:ensure_index_field, actual_scope_class, index_name, :hashkey)

            # Generate instance query method (e.g., company.find_by_badge_number)
            actual_scope_class.class_eval do
              define_method(:"find_by_#{field}") do |provided_value|
                # Use declared field accessor instead of manual instantiation
                index_hash = send(index_name)

                # Get the identifier from the hash using .get method.
                # We use .get instead of [] because it's part of the standard interface
                # common across all DataType classes (List, UnsortedSet, SortedSet, HashKey).
                # While unique indexes always use HashKey, using .get maintains consistency
                # with the broader DataType API patterns used throughout Familia.
                record_id = index_hash.get(provided_value)
                return nil unless record_id

                indexed_class.find_by_identifier(record_id)
              end

              # Generate bulk query method (e.g., company.find_all_by_badge_number)
              define_method(:"find_all_by_#{field}") do |provided_ids|
                provided_ids = Array(provided_ids)
                return [] if provided_ids.empty?

                # Use declared field accessor instead of manual instantiation
                index_hash = send(index_name)

                # Get all identifiers from the hash
                record_ids = index_hash.values_at(*provided_ids.map(&:to_s))
                # Filter out nil values and instantiate objects
                record_ids.compact.map { |record_id|
                  indexed_class.find_by_identifier(record_id)
                }
              end

              # Accessor method already created by ensure_index_field above
              # No need to manually define it here

              # Generate method to rebuild the unique index for this parent instance
              define_method(:"rebuild_#{index_name}") do
                # Use declared field accessor instead of manual instantiation
                index_hash = send(index_name)

                # Clear existing index using DataType method
                index_hash.clear

                # Rebuild from all existing objects
                # This would need to scan through all objects belonging to this parent
                # Implementation depends on how objects are stored/tracked
              end
            end
          end

          # Generates mutation methods ON THE INDEXED CLASS (Employee)
          #
          # Instance methods for scope-scoped unique index operations:
          # - employee.add_to_company_badge_index(company) - automatically validates uniqueness
          # - employee.remove_from_company_badge_index(company)
          # - employee.update_in_company_badge_index(company, old_badge)
          # - employee.guard_unique_company_badge_index!(company) - manual validation
          #
          # @param indexed_class [Class] The class being indexed (e.g., Employee)
          # @param field [Symbol] The field to index (e.g., :badge_number)
          # @param scope_class [Class] The scope class providing uniqueness context (e.g., Company)
          # @param index_name [Symbol] Name of the index (e.g., :badge_index)
          def generate_mutation_methods_self(indexed_class, field, scope_class, index_name)
            scope_class_config = scope_class.config_name
            indexed_class.class_eval do
              method_name = :"add_to_#{scope_class_config}_#{index_name}"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                field_value = send(field)
                return unless field_value

                # Automatically validate uniqueness before adding to index, but skip inside a transaction
                unless Fiber[:familia_transaction]
                  guard_method = :"guard_unique_#{scope_class_config}_#{index_name}!"
                  send(guard_method, scope_instance) if respond_to?(guard_method)
                end

                # Use declared field accessor on scope instance
                index_hash = scope_instance.send(index_name)

                # Set the value (guard already validated uniqueness)
                index_hash[field_value.to_s] = identifier
              end

              # Add a guard method to enforce unique constraint on this instance-scoped index
              #
              # @param scope_instance [Object] The scope instance providing uniqueness context (e.g., a Company)
              # @raise [Familia::RecordExistsError] if a record with the same field value
              #   exists in the scope's index. Values are compared as strings.
              # @return [void]
              #
              # @example
              #   employee.guard_unique_company_badge_index!(company)
              #
              method_name = :"guard_unique_#{scope_class_config}_#{index_name}!"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                field_value = send(field)
                return unless field_value

                # Use declared field accessor on scope instance
                index_hash = scope_instance.send(index_name)
                existing_id = index_hash.get(field_value.to_s)

                if existing_id && existing_id != identifier
                  raise Familia::RecordExistsError,
                    "#{self.class} exists in #{scope_instance.class} with #{field}=#{field_value}"
                end
              end

              method_name = :"remove_from_#{scope_class_config}_#{index_name}"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance|
                return unless scope_instance

                field_value = send(field)
                return unless field_value

                # Use declared field accessor on scope instance
                index_hash = scope_instance.send(index_name)

                # Remove using HashKey DataType method
                index_hash.remove(field_value.to_s)
              end

              method_name = :"update_in_#{scope_class_config}_#{index_name}"
              Familia.ld("[UniqueIndexGenerators] #{name} method #{method_name}")

              define_method(method_name) do |scope_instance, old_field_value = nil|
                return unless scope_instance

                new_field_value = send(field)

                # Use Familia's transaction method for atomicity with DataType abstraction
                scope_instance.transaction do |_tx|
                  # Use declared field accessor on scope instance
                  index_hash = scope_instance.send(index_name)

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
            # Generate class-level single record method
            indexed_class.define_singleton_method(:"find_by_#{field}") do |provided_id|
              index_hash = send(index_name) # access the class-level hashkey DataType

              # Get the identifier from the db hashkey using .get method.
              #
              # We use .get instead of [] because it's part of the standard interface
              # common across all DataType classes (List, UnsortedSet, SortedSet, HashKey).
              # While unique indexes always use HashKey, using .get maintains consistency
              # with the broader DataType API patterns used throughout Familia.
              record_id = index_hash.get(provided_id)

              return nil unless record_id

              indexed_class.find_by_identifier(record_id)
            end

            # Generate class-level bulk query method
            indexed_class.define_singleton_method(:"find_all_by_#{field}") do |provided_ids|
              # Check the inputs before dealing with the field since we may not need to
              provided_ids = Array(provided_ids)
              return [] if provided_ids.empty?

              index_hash = send(index_name) # access the class-level hashkey DataType

              # Get multiple identifiers from the db hashkey using .values_at
              record_ids = index_hash.values_at(*provided_ids.map(&:to_s))

              # Filter out nil values and instantiate objects
              #
              # TODO: Resolve compact/nil ambiguity. If we just called .to_s on them
              # there won't be any nils here. If we call compact after the map here
              # we'll filter out identifiers that returned no record but then the
              # number of output elements will be less than the number of input
              # elements. We need a decision there and also probably to add a
              # compact in the guard `provided_ids.compact.empty?`.
              record_ids.compact.map { |record_id|
                indexed_class.find_by_identifier(record_id)
              }
            end

            # The index accessor method is already created by the class_hashkey declaration
            # No need to manually create it - Horreum handles this automatically

            # Generate method to rebuild the class-level index
            indexed_class.define_singleton_method(:"rebuild_#{index_name}") do
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
              define_method(:"add_to_class_#{index_name}") do
                index_hash = self.class.send(index_name)  # Access the class-level hashkey DataType
                field_value = send(field)

                return unless field_value

                # Just set the value - uniqueness should be validated before save
                index_hash[field_value.to_s] = identifier
              end

              # Add a guard method to enforce unique constraint on this specific index
              #
              # @raise [Familia::RecordExistsError] if a record with the same
              # field value exists. Values are compared as strings.
              #
              # @return [void]
              define_method(:"guard_unique_#{index_name}!") do
                field_value = send(field)
                return unless field_value

                index_hash = self.class.send(index_name)
                existing_id = index_hash.get(field_value.to_s)

                if existing_id && existing_id != identifier
                  raise Familia::RecordExistsError, "#{self.class} exists #{field}=#{field_value}"
                end
              end

              define_method(:"remove_from_class_#{index_name}") do
                index_hash = self.class.send(index_name)  # Access the class-level hashkey DataType
                field_value = send(field)

                return unless field_value

                index_hash.remove(field_value.to_s)
              end

              define_method(:"update_in_class_#{index_name}") do |old_field_value = nil|
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
