# lib/familia/features/relationships/indexing.rb
#
# frozen_string_literal: true

require_relative 'indexing_relationship'
require_relative 'indexing/multi_index_generators'
require_relative 'indexing/unique_index_generators'
require_relative 'indexing/rebuild_strategies'

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
      # Instance-scoped indexes (with within:) require an initial manual add_to_*
      # call to establish the scope context. Subsequent saves auto-refresh tracked
      # scopes, and destroy! auto-removes all tracked entries (#282).
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
          def multi_index(field, index_name, within: :class, query: true)
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
          #
          # @param opts [Hash] Options forwarded to the DataType declaration
          #   (e.g. +class:+ and +reference: true+ so the index hashkey is a
          #   proper reference type that works with +each_record+).
          def ensure_index_field(scope_class, index_name, field_type, opts = {})
            return if scope_class.method_defined?(index_name) || scope_class.respond_to?(index_name)

            scope_class.send(field_type, index_name, opts)
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

              if config.class_level?
                send("update_in_class_#{index_name}", old_field_value)
              else
                next unless scope_context

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

              if config.class_level?
                send("remove_from_class_#{index_name}")
              else
                next unless scope_context

                scope_class_config = Familia.resolve_class(config.scope_class).config_name
                send("remove_from_#{scope_class_config}_#{index_name}", scope_context)
              end
            end
          end

          # Auto-update instance-scoped indexes on save using the reverse
          # index tracker. Called after the save transaction completes.
          # Only refreshes entries for scope instances previously registered
          # via add_to_* calls; the initial add_to_* remains manual.
          def auto_update_instance_indexes
            return unless _has_instance_scoped_indexes?

            entries = _index_scope_tracker.members
            return if entries.empty?

            entries.each do |entry|
              scope_config, idx_name, scope_id = entry.split("\t", 3)
              next unless scope_config && idx_name && scope_id

              config = self.class.indexing_relationships.find { |rel|
                !rel.class_level? && rel.index_name.to_s == idx_name
              }
              next unless config

              scope_instance = _build_scope_stub(config.scope_class, scope_id)
              add_method = :"add_to_#{scope_config}_#{idx_name}"
              send(add_method, scope_instance) if respond_to?(add_method)
            end
          end

          # Read instance-scoped index tracker entries. Must be called
          # BEFORE entering a MULTI/EXEC transaction since SMEMBERS
          # inside MULTI returns futures, not values.
          #
          # @return [Array<String>] tracker entries, empty if none
          def read_instance_index_scopes
            return [] unless _has_instance_scoped_indexes?

            _index_scope_tracker.members
          end

          # Remove instance-scoped index entries using pre-read tracker
          # data. Safe to call inside a MULTI/EXEC transaction since all
          # operations are writes (HDEL, SREM, DEL).
          #
          # @param tracked_entries [Array<String>] entries from read_instance_index_scopes
          def remove_tracked_index_entries!(tracked_entries)
            return if tracked_entries.nil? || tracked_entries.empty?

            tracked_entries.each do |entry|
              scope_config, idx_name, scope_id = entry.split("\t", 3)
              next unless scope_config && idx_name && scope_id

              config = self.class.indexing_relationships.find { |rel|
                !rel.class_level? && rel.index_name.to_s == idx_name
              }
              next unless config

              scope_instance = _build_scope_stub(config.scope_class, scope_id)
              remove_method = :"remove_from_#{scope_config}_#{idx_name}"
              send(remove_method, scope_instance) if respond_to?(remove_method)
            end

            _index_scope_tracker.delete!
          end

          # Record that this object was added to an instance-scoped index.
          # Called by the generated add_to_* methods.
          def _record_index_scope(scope_config, index_name, scope_instance)
            entry = "#{scope_config}\t#{index_name}\t#{scope_instance.identifier}"
            _index_scope_tracker.add(entry)
          end

          # Remove a scope tracking entry. Called by the generated
          # remove_from_* methods.
          def _unrecord_index_scope(scope_config, index_name, scope_instance)
            entry = "#{scope_config}\t#{index_name}\t#{scope_instance.identifier}"
            _index_scope_tracker.remove(entry)
          end

          # Fail fast when this object has never been persisted. Called by the
          # generated add_to_*/update_in_* methods (both instance-scoped and
          # class-level variants) before any write. An index entry stores this
          # object's identifier, so indexing an unsaved object plants a
          # dangling pointer in the index — and if the process never saves, no
          # tracker entry or destroy! pass can find it to clean up.
          #
          # Skipped inside a transaction/pipeline, where the EXISTS probe would
          # queue into the caller's MULTI and return a Future instead of a
          # boolean (same conservatism as DataType#warn_if_dirty!). This is
          # also what keeps the save path working: auto_update_class_indexes
          # and the rebuild strategies call these methods inside a MULTI,
          # where the object hash write is queued alongside the index write.
          #
          # @param index_name [Symbol] the index being written
          # @param scope_instance [Object, nil] scope for instance-scoped
          #   indexes; nil for class-level indexes
          def _ensure_persisted_before_index_write!(index_name, scope_instance = nil)
            return if Fiber[:familia_transaction]
            return if exists?

            location = if scope_instance
                         "#{index_name} on #{scope_instance.class.name}"
                       else
                         "class-level #{index_name}"
                       end
            raise Familia::PersistenceError,
                  "Cannot index unsaved #{self.class.name} in #{location}: " \
                  'the index entry would point to a record that does not ' \
                  'exist in the database yet. Call #save first.'
          end

          def _has_instance_scoped_indexes?
            return false unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.any? { |rel| !rel.class_level? }
          end

          def _index_scope_tracker
            @_index_scope_tracker ||= Familia::UnsortedSet.new(
              Familia.join('_idx_scopes'), parent: self
            )
          end

          # Build a minimal scope instance for Redis key resolution
          # without loading the full object from the database.
          def _build_scope_stub(scope_class, scope_id)
            id_field = scope_class.identifier_field
            case id_field
            when Symbol, String
              scope_class.new(id_field.to_sym => scope_id)
            else
              scope_class.find_by_identifier(scope_id)
            end
          end
          private :_index_scope_tracker, :_build_scope_stub, :_has_instance_scoped_indexes?

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

              # Class-level indexes have within: nil (unique_index) or within: :class (multi_index)
              # Instance-scoped indexes have within: SomeClass (a specific class)
              if config.within.nil? || config.within == :class
                if cardinality == :unique
                  # Class-level unique index - check hash key using DataType
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
                  # Class-level multi index - check set membership using factory method
                  index_set = self.class.send("#{index_name}_for", field_value)
                  next unless index_set.member?(identifier)

                  memberships << {
                    scope_class: 'class',
                    index_name: index_name,
                    field: field,
                    field_value: field_value,
                    index_key: index_set.dbkey,
                    cardinality: cardinality,
                    type: 'multi_index',
                  }
                end
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
          # For class-level indexes, checks the hash key (unique) or set membership (multi)
          # For instance-scoped indexes, returns false (requires scope instance)
          def indexed_in?(index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel.index_name == index_name }
            return false unless config

            field = config.field
            field_value = send(field)
            return false unless field_value

            # Class-level indexes have within: nil (unique_index) or within: :class (multi_index)
            # Instance-scoped indexes have within: SomeClass (a specific class)
            if config.within.nil? || config.within == :class
              if config.cardinality == :unique
                # Class-level unique index - check hash key using DataType
                index_hash = self.class.send(index_name)
                index_hash.key?(field_value.to_s)
              else
                # Class-level multi index - check set membership using factory method
                index_set = self.class.send("#{index_name}_for", field_value)
                index_set.member?(identifier)
              end
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
