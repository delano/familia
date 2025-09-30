# lib/familia/features/relationships/indexing.rb

require_relative 'indexing/multi_index_generators'
require_relative 'indexing/unique_index_generators'

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
          extend MultiIndexGenerators
          extend UniqueIndexGenerators
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
            target = resolve_target_class(target_class)

            # Store metadata for this indexing relationship
            indexing_relationships << {
              field: field,
              target_class: target_class,
              target_class_name: target[:name],
              index_name: index_name,
              finder: finder,
              cardinality: :multi,
            }

            # Generate query methods on the parent class
            MultiIndexGenerators.generate_query_methods_destination(target_class, field, index_name, self) if finder && target_class.is_a?(Class)

            # Generate mutation methods on the indexed class
            MultiIndexGenerators.generate_mutation_methods_self(target[:snake], field, index_name, self)
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
              target = resolve_target_class(target_class)

              # Store metadata for instance-scoped unique index
              indexing_relationships << {
                field: field,
                target_class: target_class,
                target_class_name: target[:name],
                index_name: index_name,
                finder: finder,
                cardinality: :unique,
              }

              # Generate query methods on the parent class
              UniqueIndexGenerators.generate_query_methods_destination(target_class, field, index_name, self) if finder && target_class.is_a?(Class)

              # Generate mutation methods on the indexed class
              UniqueIndexGenerators.generate_mutation_methods_self(target[:snake], field, index_name, self)
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

              # Generate class-level query and mutation methods
              UniqueIndexGenerators.generate_query_methods_class(field, index_name, self) if finder
              UniqueIndexGenerators.generate_mutation_methods_class(field, index_name, self)
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

          # Resolve target class to name and snake_case versions
          # Eliminates duplicate resolution logic in multi_index and unique_index
          #
          # @param target [Class, Symbol, String] Target class or identifier
          # @return [Hash] { name: "Company", snake: "company" }
          def resolve_target_class(target)
            if target.is_a?(Class)
              {
                name: target.name,
                snake: target.name.demodularize.snake_case
              }
            else
              {
                name: target.to_s,
                snake: target.to_s
              }
            end
          end

          # Helper method to pascalize a word without ActiveSupport dependency
          def camelize_word(word)
            word.to_s.split('_').map(&:capitalize).join
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
