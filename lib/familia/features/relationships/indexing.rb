# lib/familia/features/relationships/indexing.rb

require_relative 'indexing_relationship'
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
      #   user.save  # Automatically populates email_lookup index
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
      # - within: scope class providing uniqueness boundary for instance-scoped indexes
      # - query: whether to generate find_by_* methods (default: true)
      # - query: whether to generate find_by_* methods (default: true)
      #
      # Key Patterns:
      # - Class unique: "user:email_index" → HashKey
      # - Instance unique: "company:c1:badge_index" → HashKey
      # - Instance multi: "company:c1:dept_index:engineering" → UnsortedSet
      #
      # Auto-Indexing:
      # Class-level unique_index declarations automatically populate on save():
      #   user = User.new(email: 'test@example.com')
      #   user.save  # Auto-indexes email → user_id
      # Instance-scoped indexes (with within:) remain manual (require parent context).
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
          # @param within [Class, Symbol] The scope class providing uniqueness context
          # @param query [Boolean] Whether to generate query methods
          #
          # @example Instance-scoped multi-value indexing
          #   multi_index :department, :dept_index, within: Company
          #
          def multi_index(field, index_name, within:, query: true)
            MultiIndexGenerators.setup(
              indexed_class: self,
              field: field,
              index_name: index_name,
              within: within,
              query: query,
            )
          end

          # Define a unique index lookup (1:1 mapping)
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index hash
          # @param within [Class, Symbol] Optional scope class for instance-scoped unique index
          # @param query [Boolean] Whether to generate query methods
          #
          # @example Class-level unique index
          #   unique_index :email, :email_lookup
          #   unique_index :username, :username_lookup, query: false
          #
          # @example Instance-scoped unique index
          #   unique_index :badge_number, :badge_index, within: Company
          #
          def unique_index(field, index_name, within: nil, query: true)
            UniqueIndexGenerators.setup(
              indexed_class: self,
              field: field,
              index_name: index_name,
              within: within,
              query: query,
            )
          end

          # Get all indexing relationships for this class
          def indexing_relationships
            @indexing_relationships ||= []
          end

          # Ensure proper DataType field is declared for index
          # Similar to ensure_collection_field in participation system
          def ensure_index_field(scope_class, index_name, field_type)
            return if scope_class.method_defined?(index_name) || scope_class.respond_to?(index_name)

            scope_class.send(field_type, index_name)
          end
        end

        # Instance methods for indexed objects
        module ModelInstanceMethods
          # Update all indexes for a given scope context
          # For class-level indexes (unique_index without within:), scope_context should be nil
          # For instance-scoped indexes (with within:), scope_context should be the scope instance
          def update_all_indexes(old_values = {}, scope_context = nil)
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              field = config.field
              index_name = config.index_name
              old_field_value = old_values[field]

              # Determine which update method to call
              if config.within.nil?
                # Class-level index (unique_index without within:)
                send("update_in_class_#{index_name}", old_field_value)
              else
                # Instance-scoped index (unique_index or multi_index with within:) - requires scope context
                next unless scope_context

                # Use config_name for method naming
                scope_class_config = Familia.resolve_class(config.scope_class).config_name
                send("update_in_#{scope_class_config}_#{index_name}", scope_context, old_field_value)
              end
            end
          end

          # Remove from all indexes for a given scope context
          # For class-level indexes (unique_index without within:), scope_context should be nil
          # For instance-scoped indexes (with within:), scope_context should be the scope instance
          def remove_from_all_indexes(scope_context = nil)
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              index_name = config.index_name

              # Determine which remove method to call
              if config.within.nil?
                # Class-level index (unique_index without within:)
                send("remove_from_class_#{index_name}")
              else
                # Instance-scoped index (unique_index or multi_index with within:) - requires scope context
                next unless scope_context

                # Use config_name for method naming
                scope_class_config = Familia.resolve_class(config.scope_class).config_name
                send("remove_from_#{scope_class_config}_#{index_name}", scope_context)
              end
            end
          end

          # Get all indexes this object appears in
          # Note: For instance-scoped indexes, this only shows class-level indexes
          # since instance-scoped indexes require a specific scope instance
          #
          # @return [Array<Hash>] Array of index information
          def current_indexings
            return [] unless self.class.respond_to?(:indexing_relationships)

            memberships = []

            self.class.indexing_relationships.each do |config|
              field = config.field
              index_name = config.index_name
              cardinality = config.cardinality
              field_value = send(field)

              next unless field_value

              if config.within.nil?
                # Class-level index (unique_index without within:) - check hash key using DataType
                index_hash = self.class.send(index_name)
                next unless index_hash.key?(field_value.to_s)

                memberships << {
                  scope_class: 'class',
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: index_hash.dbkey,
                  cardinality: cardinality,
                  type: 'unique_index',
                }
              else
                # Instance-scoped index (unique_index or multi_index with within:) - cannot check without scope instance
                # This would require scanning all possible scope instances
                memberships << {
                  scope_class: config.scope_class_config_name,
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: 'scope_dependent',
                  cardinality: cardinality,
                  type: cardinality == :unique ? 'unique_index' : 'multi_index',
                  note: 'Requires scope instance for verification',
                }
              end
            end

            memberships
          end

          # Check if this object is indexed in a specific scope
          # For class-level indexes, checks the hash key
          # For instance-scoped indexes, returns false (requires scope instance)
          def indexed_in?(index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel.index_name == index_name }
            return false unless config

            field = config.field
            field_value = send(field)
            return false unless field_value

            if config.within.nil?
              # Class-level index (class_indexed_by) - check hash key using DataType
              index_hash = self.class.send(index_name)
              index_hash.key?(field_value.to_s)
            else
              # Instance-scoped index (with within:) - cannot verify without scope instance
              false
            end
          end
        end
      end
    end
  end
end
