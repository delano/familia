# lib/familia/features/relationships/indexing.rb

module Familia
  module Features
    module Relationships
      # Indexing module for indexed_by relationships using Redis hashes
      # Provides O(1) lookups for finding objects by field values
      module Indexing
        using Familia::Refinements::SnakeCase

        # Class-level indexing configurations
        def self.included(base)
          base.extend ClassMethods
          base.include InstanceMethods
          super
        end

        # Indexing::ClassMethods
        #
        module ClassMethods
          # Define an indexed_by relationship for fast lookups
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index hash
          # @param parent [Class, Symbol] The parent class that owns the index
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Basic indexing
          #   indexed_by :display_name, parent: Customer, index_name: :domain_index
          #
          # @example Parent-based indexing
          #   indexed_by :user_id, :user_memberships, parent: User
          def indexed_by(field, index_name, parent:, finder: true)
            context_class = parent
            context_class_name = if context_class.is_a?(Class)
                                   # Extract just the class name without module prefixes or object ids
                                   context_class.name.snake_case
                                 else
                                   # For symbol parent, convert to string
                                   context_class.to_s
                                 end

            # Store metadata for this indexing relationship
            indexing_relationships << {
              field: field,
              context_class: context_class,
              context_class_name: context_class_name,
              index_name: index_name,
              finder: finder,
            }

            # Generate finder methods on the context class
            if finder && context_class.is_a?(Class)
              generate_context_finder_methods(context_class, field, index_name)
            end

            # Generate instance methods for relationship indexing
            generate_relationship_index_methods(context_class_name, field, index_name)
          end

          # Define a class-level indexed lookup
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index hash
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Class-level indexing (using class_ prefix convention)
          #   class_indexed_by :email, :email_lookup
          #   class_indexed_by :username, :username_lookup, finder: false
          #
          def class_indexed_by(field, index_name, finder: true)
            # Store metadata for this indexing relationship
            indexing_relationships << {
              field: field,
              context_class: self,
              context_class_name: name,
              index_name: index_name,
              finder: finder,
            }

            # Generate class-level finder methods if requested
            generate_class_finder_methods(field, index_name) if finder

            # Generate instance methods for class-level indexing
            generate_direct_index_methods(field, index_name)
          end

          # Get all indexing relationships for this class
          def indexing_relationships
            @indexing_relationships ||= [] # rubocop:disable ThreadSafety/ClassInstanceVariable
          end

          private

          # Helper method to camelize a word without ActiveSupport dependency
          def camelize_word(word)
            word.to_s.split('_').map(&:capitalize).join
          end

          # Generate finder methods on the context class (e.g., Customer.find_by_display_name)
          def generate_context_finder_methods(context_class, field, index_name)
            # Resolve context class if it's a symbol/string
            actual_context_class = context_class.is_a?(Class) ? context_class : Object.const_get(camelize_word(context_class))

            # Store reference to the indexed class for the finder methods
            indexed_class = self

            # Generate finder method (e.g., Customer.find_by_display_name)
            actual_context_class.define_singleton_method("find_by_#{field}") do |field_value|
              index_key = "#{self.name.downcase}:#{index_name}"
              object_id = dbclient.hget(index_key, field_value.to_s)

              return nil unless object_id

              indexed_class.new(object_id)
            end

            # Generate bulk finder method (e.g., Customer.find_all_by_display_name)
            actual_context_class.define_singleton_method("find_all_by_#{field}") do |field_values|
              return [] if field_values.empty?

              index_key = "#{self.name.downcase}:#{index_name}"
              object_ids = dbclient.hmget(index_key, *field_values.map(&:to_s))

              # Filter out nil values and instantiate objects
              object_ids.compact.map { |object_id| indexed_class.new(object_id) }
            end

            # Generate method to get the index hash directly
            actual_context_class.define_singleton_method(index_name) do
              index_key = "#{self.name.downcase}:#{index_name}"
              Familia::HashKey.new(nil, dbkey: index_key, logical_database: logical_database)
            end

            # Generate method to rebuild the index
            actual_context_class.define_singleton_method("rebuild_#{index_name}") do
              index_key = "#{self.name.downcase}:#{index_name}"

              # Clear existing index
              dbclient.del(index_key)

              # This is a simplified version - in practice, you'd need to iterate
              # through all objects that should be in this index
              # Implementation would depend on how you track which objects belong to this context
            end
          end

          # Generate class-level finder methods
          def generate_class_finder_methods(field, index_name)
            # Generate class-level finder method (e.g., Domain.find_by_display_name)
            define_singleton_method("find_by_#{field}") do |field_value|
              index_key = "#{self.name.downcase}:#{index_name}"
              object_id = dbclient.hget(index_key, field_value.to_s)

              return nil unless object_id

              new(object_id)
            end

            # Generate class-level bulk finder method
            define_singleton_method("find_all_by_#{field}") do |field_values|
              return [] if field_values.empty?

              index_key = "#{self.name.downcase}:#{index_name}"
              object_ids = dbclient.hmget(index_key, *field_values.map(&:to_s))

              # Filter out nil values and instantiate objects
              object_ids.compact.map { |object_id| self.new(object_id) }
            end

            # Generate method to get the class-level index hash directly
            define_singleton_method("#{index_name}") do
              index_key = "#{self.name.downcase}:#{index_name}"
              Familia::HashKey.new(nil, dbkey: index_key, logical_database: logical_database)
            end

            # Generate method to rebuild the class-level index
            define_singleton_method("rebuild_#{index_name}") do
              index_key = "#{self.name.downcase}:#{index_name}"

              # Clear existing index
              dbclient.del(index_key)

              # Rebuild from all existing objects
              # This would need to scan through all objects of this class
              # Implementation depends on how objects are stored/tracked
            end
          end

          # Generate instance methods for class-level indexing (class_indexed_by)
          def generate_direct_index_methods(field, index_name)
            # Class-level index methods
            define_method("add_to_class_#{index_name}") do
              index_key = "#{self.class.name.downcase}:#{index_name}"
              field_value = send(field)

              return unless field_value

              dbclient.hset(index_key, field_value.to_s, identifier)
            end

            define_method("remove_from_class_#{index_name}") do
              index_key = "#{self.class.name.downcase}:#{index_name}"
              field_value = send(field)

              return unless field_value

              dbclient.hdel(index_key, field_value.to_s)
            end

            define_method("update_in_class_#{index_name}") do |old_field_value = nil|
              index_key = "#{self.class.name.downcase}:#{index_name}"
              new_field_value = send(field)

              dbclient.multi do |tx|
                # Remove old value if provided
                tx.hdel(index_key, old_field_value.to_s) if old_field_value

                # Add new value if present
                tx.hset(index_key, new_field_value.to_s, identifier) if new_field_value
              end
            end
          end

          # Generate instance methods for relationship indexing (indexed_by with parent:)
          def generate_relationship_index_methods(context_class_name, field, index_name)
            # All indexes are stored at class level - parent is only conceptual
            define_method("add_to_#{context_class_name.downcase}_#{index_name}") do |context_instance = nil|
              index_key = "#{self.class.name.downcase}:#{index_name}"
              field_value = send(field)

              return unless field_value

              dbclient.hset(index_key, field_value.to_s, identifier)
            end

            define_method("remove_from_#{context_class_name.downcase}_#{index_name}") do |context_instance = nil|
              index_key = "#{self.class.name.downcase}:#{index_name}"
              field_value = send(field)

              return unless field_value

              dbclient.hdel(index_key, field_value.to_s)
            end

            define_method("update_in_#{context_class_name.downcase}_#{index_name}") do |context_instance = nil, old_field_value = nil|
              index_key = "#{self.class.name.downcase}:#{index_name}"
              new_field_value = send(field)

              dbclient.multi do |tx|
                # Remove old value if provided
                tx.hdel(index_key, old_field_value.to_s) if old_field_value

                # Add new value if present
                tx.hset(index_key, new_field_value.to_s, identifier) if new_field_value
              end
            end
          end
        end

        # Instance methods for indexed objects
        module InstanceMethods
          # Update all indexes
          def update_all_indexes(old_values = {})
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              field = config[:field]
              index_name = config[:index_name]
              context_class = config[:context_class]
              old_field_value = old_values[field]

              # Determine which update method to call
              if context_class == self.class
                # Class-level index (class_indexed_by)
                send("update_in_class_#{index_name}", old_field_value)
              else
                # Relationship index (indexed_by with parent:)
                context_class_name = config[:context_class_name].downcase
                send("update_in_#{context_class_name}_#{index_name}", nil, old_field_value)
              end
            end
          end

          # Remove from all indexes
          def remove_from_all_indexes
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              index_name = config[:index_name]
              context_class = config[:context_class]

              # Determine which remove method to call
              if context_class == self.class
                # Class-level index (class_indexed_by)
                send("remove_from_class_#{index_name}")
              else
                # Relationship index (indexed_by with parent:)
                context_class_name = config[:context_class_name].downcase
                send("remove_from_#{context_class_name}_#{index_name}", nil)
              end
            end
          end

          # Get all indexes this object appears in
          #
          # @return [Array<Hash>] Array of index information
          def indexing_memberships
            return [] unless self.class.respond_to?(:indexing_relationships)

            memberships = []

            self.class.indexing_relationships.each do |config|
              field = config[:field]
              index_name = config[:index_name]
              context_class = config[:context_class]
              field_value = send(field)

              next unless field_value

              # All indexes are stored at class level
              index_key = "#{self.class.name.downcase}:#{index_name}"
              if dbclient.hexists(index_key, field_value.to_s)
                memberships << {
                  context_class: context_class == self.class ? 'class' : config[:context_class_name].downcase,
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: index_key,
                  type: context_class == self.class ? 'class_indexed_by' : 'indexed_by'
                }
              end
            end

            memberships
          end

          # Check if this object is indexed in a specific context
          def indexed_in?(index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel[:index_name] == index_name }
            return false unless config

            field = config[:field]
            field_value = send(field)
            return false unless field_value

            # For the cleaned-up API, all indexes are class-level
            index_key = "#{self.class.name.downcase}:#{index_name}"
            dbclient.hexists(index_key, field_value.to_s)
          end
        end
      end
    end
  end
end
