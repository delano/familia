# lib/familia/features/relationships/indexing.rb

module Familia
  module Features
    module Relationships
      # Indexing module for attribute-based lookups using Valkey/Redis data structures.
      # Provides O(1) field-to-object mappings without relationship semantics.
      #
      # @example Class-level unique index (1:1 mapping via HashKey)
      #   class User < Familia::Horreum
      #     feature :relationships
      #     field :email
      #     unique_index :email, :email_lookup
      #   end
      #
      #   user = User.new(user_id: 'u1', email: 'alice@example.com')
      #   user.add_to_class_email_lookup
      #   User.find_by_email('alice@example.com')  # → user
      #
      # @example Instance-scoped unique index (within parent, 1:1 via HashKey)
      #   class Employee < Familia::Horreum
      #     feature :relationships
      #     field :badge_number
      #     unique_index :badge_number, :badge_index, within: Company
      #   end
      #
      #   company = Company.new(company_id: 'c1')
      #   employee = Employee.new(emp_id: 'e1', badge_number: '12345')
      #   employee.add_to_company_badge_index(company)
      #   company.find_by_badge_number('12345')  # → employee
      #
      # @example Instance-scoped multi-value index (within parent, 1:many via UnsortedSet)
      #   class Employee < Familia::Horreum
      #     feature :relationships
      #     field :department
      #     multi_index :department, :dept_index, within: Company
      #   end
      #
      #   company = Company.new(company_id: 'c1')
      #   emp1 = Employee.new(emp_id: 'e1', department: 'engineering')
      #   emp2 = Employee.new(emp_id: 'e2', department: 'engineering')
      #   emp1.add_to_company_dept_index(company)
      #   emp2.add_to_company_dept_index(company)
      #   company.find_all_by_department('engineering')  # → [emp1, emp2]
      #
      # Terminology:
      # - unique_index: 1:1 field-to-object mapping (HashKey)
      # - multi_index: 1:many field-to-objects mapping (UnsortedSet, no scores)
      # - within: parent class for instance-scoped indexes
      # - finder: whether to generate find_by_* methods (default: true)
      #
      # Key Patterns:
      # - Class unique: "user:email_index" → HashKey
      # - Instance unique: "company:c1:badge_index" → HashKey
      # - Instance multi: "company:c1:dept_index:engineering" → UnsortedSet
      #
      # Design Philosophy:
      # Indexing is for finding objects by attribute, not ordering them.
      # Use multi_index with UnsortedSet (no temporal scores), then sort in Ruby:
      #   employees = company.find_all_by_department('eng')
      #   sorted = employees.sort_by(&:hire_date)

      module Indexing
        using Familia::Refinements::StylizeWords

        # Class-level indexing configurations
        def self.included(base)
          base.extend ModelClassMethods
          base.include ModelInstanceMethods
          super
        end

        # Indexing::ModelClassMethods
        #
        module ModelClassMethods
          # Define an indexed_by relationship for fast lookups
          #
          # Define a multi-value index (1:many mapping)
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index
          # @param within [Class, Symbol] The parent class that owns the index
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Instance-scoped multi-value indexing
          #   multi_index :department, :dept_index, within: Company
          #
          def multi_index(field, index_name, within:, finder: true)
            target_class = within

            target_class_name = if target_class.is_a?(Class)
                                  # Store the actual class name for consistency
                                  target_class.name
                                else
                                  # For symbol target, convert to string
                                  target_class.to_s
                                end

            # Get snake_case version for method naming
            target_class_snake = if target_class.is_a?(Class)
                                   target_class.name.demodularize.snake_case
                                 else
                                   target_class.to_s
                                 end

            # Store metadata for this indexing relationship
            indexing_relationships << {
              field: field,
              target_class: target_class,
              target_class_name: target_class_name,
              index_name: index_name,
              finder: finder,
              cardinality: :multi,
            }

            # Ensure proper DataType fields are declared on target class for sorted_set indexes
            # This creates the needed DataType infrastructure that will be accessed by field value
            # No specific field declaration needed here - the indexes are created dynamically
            # based on field values, but we need the target class to understand index access

            # Generate finder methods on the target class
            generate_target_multi_finder_methods(target_class, field, index_name) if finder && target_class.is_a?(Class)

            # Generate instance methods for relationship indexing
            generate_relationship_multi_index_methods(target_class_snake, field, index_name)
          end

          # Define a unique index lookup (1:1 mapping)
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index hash
          # @param within [Class, Symbol] Optional parent class for instance-scoped unique index
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Class-level unique index
          #   unique_index :email, :email_lookup
          #   unique_index :username, :username_lookup, finder: false
          #
          # @example Instance-scoped unique index
          #   unique_index :badge_number, :badge_index, within: Company
          #
          def unique_index(field, index_name, within: nil, finder: true)
            # Handle instance-scoped unique index (within: parameter provided)
            if within
              target_class = within

              target_class_name = if target_class.is_a?(Class)
                                    target_class.name
                                  else
                                    target_class.to_s
                                  end

              #
              target_class_snake = if target_class.is_a?(Class)
                                     target_class.name.demodularize.snake_case
                                   else
                                     target_class.to_s
                                   end

              # Store metadata for instance-scoped unique index
              indexing_relationships << {
                field: field,
                target_class: target_class,
                target_class_name: target_class_name,
                index_name: index_name,
                finder: finder,
                cardinality: :unique,
              }

              # Generate finder methods on the target class
              generate_target_unique_finder_methods(target_class, field, index_name) if finder && target_class.is_a?(Class)

              # Generate instance methods for instance-scoped unique indexing
              generate_relationship_unique_index_methods(target_class_snake, field, index_name)
            else
              # Class-level unique index (no within: parameter)
              # Store metadata for this indexing relationship
              indexing_relationships << {
                field: field,
                target_class: self,
                target_class_name: name,
                index_name: index_name,
                finder: finder,
                cardinality: :unique,
              }

              # Ensure proper DataType field is declared for the index
              ensure_index_field(self, index_name, :class_hashkey)

              # Generate class-level finder methods if requested
              generate_class_unique_finder_methods(field, index_name) if finder

              # Generate instance methods for class-level indexing
              generate_class_unique_index_methods(field, index_name)
            end
          end

          # Get all indexing relationships for this class
          def indexing_relationships
            @indexing_relationships ||= []
          end

          # Ensure proper DataType field is declared for index
          # Similar to ensure_collection_field in participation system
          def ensure_index_field(target_class, index_name, field_type)
            return if target_class.method_defined?(index_name) || target_class.respond_to?(index_name)

            target_class.send(field_type, index_name)
          end

          private

          # Helper method to pascalize a word without ActiveSupport dependency
          def camelize_word(word)
            word.to_s.split('_').map(&:capitalize).join
          end

          # Generate finder methods on the target class (e.g., company.find_by_department)
          def generate_target_multi_finder_methods(target_class, field, index_name)
            # Resolve target class if it's a symbol/string
            actual_target_class = target_class.is_a?(Class) ? target_class : Object.const_get(camelize_word(target_class))

            # Store reference to the indexed class for the finder methods
            indexed_class = self

            # Generate instance finder method (e.g., company.find_by_department)
            actual_target_class.class_eval do
              define_method("find_by_#{field}") do |field_value|
              # Create DataType for this specific field value index using proper Horreum pattern
              index_key = "#{index_name}:#{field_value}"
              index_set = Familia::UnsortedSet.new(index_key, parent: self)

                # Get first member from set
              members = index_set.members.first(1)
                return nil if members.empty?

                indexed_class.new(members.first)
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

          # Generate finder methods on the target class for unique indexes (e.g., company.find_by_badge_number)
          def generate_target_unique_finder_methods(target_class, field, index_name)
            # Resolve target class if it's a symbol/string
            actual_target_class = target_class.is_a?(Class) ? target_class : Object.const_get(camelize_word(target_class))

            # Store reference to the indexed class for the finder methods
            indexed_class = self

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

          # Generate class-level finder methods
          def generate_class_unique_finder_methods(field, index_name)
            # Generate class-level finder method (e.g., Domain.find_by_display_name)
            define_singleton_method("find_by_#{field}") do |field_value|
              index_hash = send(index_name) # Access the class-level hashkey DataType
              object_id = index_hash[field_value.to_s]

              return nil unless object_id

              new(object_id)
            end

            # Generate class-level bulk finder method
            define_singleton_method("find_all_by_#{field}") do |field_values|
              return [] if field_values.empty?

              index_hash = send(index_name) # Access the class-level hashkey DataType
              object_ids = index_hash.values_at(*field_values.map(&:to_s))
              # Filter out nil values and instantiate objects
              object_ids.compact.map { |object_id| new(object_id) }
            end

            # The index accessor method is already created by the class_hashkey declaration
            # No need to manually create it - Horreum handles this automatically

            # Generate method to rebuild the class-level index
            define_singleton_method("rebuild_#{index_name}") do
              index_hash = send(index_name) # Access the class-level hashkey DataType

              # Clear existing index using DataType method
              index_hash.clear

              # Rebuild from all existing objects
              # This would need to scan through all objects of this class
              # Implementation depends on how objects are stored/tracked
            end
          end

          # Generate instance methods for class-level indexing (class_indexed_by)
          def generate_class_unique_index_methods(field, index_name)
            # Class-level index methods using DataType operations
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

          # Generate instance methods for multi-value relationship indexing (multi_index with within:)
          def generate_relationship_multi_index_methods(target_class_name, field, index_name)
            # Multi-value indexes are scoped to parent instances using UnsortedSets

            method_name = "add_to_#{target_class_name}_#{index_name}"
            Familia.ld("[generate_relationship_index_methods] #{name} method #{method_name}")

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

            method_name = "remove_from_#{target_class_name}_#{index_name}"
            Familia.ld("[generate_relationship_index_methods] #{name} method #{method_name}")

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

            method_name = "update_in_#{target_class_name}_#{index_name}"
            Familia.ld("[generate_relationship_index_methods] #{name} method #{method_name}")

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

          # Generate instance methods for relationship unique indexing (unique_index with within:)
          def generate_relationship_unique_index_methods(target_class_name, field, index_name)
            # Unique indexes are scoped to parent instances using HashKeys

            method_name = "add_to_#{target_class_name}_#{index_name}"
            Familia.ld("[generate_relationship_unique_index_methods] #{name} method #{method_name}")

            define_method(method_name) do |target_instance|
              return unless target_instance

              field_value = send(field)
              return unless field_value

              # Create HashKey DataType for this parent instance
              index_hash = Familia::HashKey.new(index_name, parent: target_instance)

              # Use HashKey DataType method
              index_hash[field_value.to_s] = identifier
            end

            method_name = "remove_from_#{target_class_name}_#{index_name}"
            Familia.ld("[generate_relationship_unique_index_methods] #{name} method #{method_name}")

            define_method(method_name) do |target_instance|
              return unless target_instance

              field_value = send(field)
              return unless field_value

              # Create HashKey DataType for this parent instance
              index_hash = Familia::HashKey.new(index_name, parent: target_instance)

              # Remove using HashKey DataType method
              index_hash.remove(field_value.to_s)
            end

            method_name = "update_in_#{target_class_name}_#{index_name}"
            Familia.ld("[generate_relationship_unique_index_methods] #{name} method #{method_name}")

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

        # Instance methods for indexed objects
        module ModelInstanceMethods
          # Update all indexes for a given parent context
          # For class-level indexes (class_indexed_by), parent_context should be nil
          # For relationship indexes (indexed_by), parent_context should be the parent instance
          def update_all_indexes(old_values = {}, parent_context = nil)
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              field = config[:field]
              index_name = config[:index_name]
              target_class = config[:target_class]
              old_field_value = old_values[field]

              # Determine which update method to call
              if target_class == self.class
                # Class-level index (unique_index without within:)
                send("update_in_class_#{index_name}", old_field_value)
              else
                # Relationship index (unique_index or multi_index with within:) - requires parent context
                next unless parent_context

                # Use snake_case for method naming
                target_class_snake = config[:target_class].name.demodularize.snake_case
                send("update_in_#{target_class_snake}_#{index_name}", parent_context, old_field_value)
              end
            end
          end

          # Remove from all indexes for a given parent context
          # For class-level indexes (class_indexed_by), parent_context should be nil
          # For relationship indexes (indexed_by), parent_context should be the parent instance
          def remove_from_all_indexes(parent_context = nil)
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              index_name = config[:index_name]
              target_class = config[:target_class]

              # Determine which remove method to call
              if target_class == self.class
                # Class-level index (unique_index without within:)
                send("remove_from_class_#{index_name}")
              else
                # Relationship index (unique_index or multi_index with within:) - requires parent context
                next unless parent_context

                # Use snake_case for method naming
                target_class_snake = config[:target_class].name.demodularize.snake_case
                send("remove_from_#{target_class_snake}_#{index_name}", parent_context)
              end
            end
          end

          # Get all indexes this object appears in
          # Note: For target-scoped indexes, this only shows class-level indexes
          # since target-scoped indexes require a specific target instance
          #
          # @return [Array<Hash>] Array of index information
          def indexing_memberships
            return [] unless self.class.respond_to?(:indexing_relationships)

            memberships = []

            self.class.indexing_relationships.each do |config|
              field = config[:field]
              index_name = config[:index_name]
              target_class = config[:target_class]
              cardinality = config[:cardinality]
              field_value = send(field)

              next unless field_value

              if target_class == self.class
                # Class-level index (unique_index without within:) - check hash key using DataType
                index_hash = self.class.send(index_name)
                next unless index_hash.key?(field_value.to_s)

                memberships << {
                  target_class: 'class',
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: index_hash.dbkey,
                  cardinality: cardinality,
                  type: 'unique_index',
                }
              else
                # Instance-scoped index (unique_index or multi_index with within:) - cannot check without target instance
                # This would require scanning all possible target instances
                memberships << {
                  target_class: config[:target_class_name].demodularize.snake_case,
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: 'target_dependent',
                  cardinality: cardinality,
                  type: cardinality == :unique ? 'unique_index' : 'multi_index',
                  note: 'Requires target instance for verification',
                }
              end
            end

            memberships
          end

          # Check if this object is indexed in a specific target
          # For class-level indexes, checks the hash key
          # For target-scoped indexes, returns false (requires target instance)
          def indexed_in?(index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel[:index_name] == index_name }
            return false unless config

            field = config[:field]
            field_value = send(field)
            return false unless field_value

            target_class = config[:target_class]

            if target_class == self.class
              # Class-level index (class_indexed_by) - check hash key using DataType
              index_hash = self.class.send(index_name)
              index_hash.key?(field_value.to_s)
            else
              # Target-scoped index (indexed_by) - cannot verify without target instance
              false
            end
          end
        end
      end
    end
  end
end
