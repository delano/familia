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
          # @param index_name [Symbol] Name of the index
          # @param context [Class, Symbol] The context class that owns the index
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Context-based indexing
          #   indexed_by :display_name, :domain_index, context: Customer
          #
          # @example Global indexing
          #   indexed_by :display_name, :global_domain_index, context: :global
          def indexed_by(field, index_name, context:, finder: true)
            context_class = context

            # Handle special :global context for class-level indexing
            return class_indexed_by(field, index_name, finder: finder) if context == :global

            context_class_name = if context_class.is_a?(Class)
                                   # Store the actual class name for consistency
                                   context_class.name
                                 else
                                   # For symbol context, convert to string
                                   context_class.to_s
                                 end

            # Get snake_case version for method naming
            context_class_snake = if context_class.is_a?(Class)
                                    context_class.name.snake_case
                                  else
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
            generate_context_finder_methods(context_class, field, index_name) if finder && context_class.is_a?(Class)

            # Generate instance methods for relationship indexing
            generate_relationship_index_methods(context_class_snake, field, index_name)
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

          # Generate finder methods on the context class (e.g., company.find_by_department)
          def generate_context_finder_methods(context_class, field, index_name)
            # Resolve context class if it's a symbol/string
            actual_context_class = context_class.is_a?(Class) ? context_class : Object.const_get(camelize_word(context_class))

            # Store reference to the indexed class for the finder methods
            indexed_class = self

            # Generate instance finder method (e.g., company.find_by_department)
            actual_context_class.class_eval do
              define_method("find_by_#{field}") do |field_value|
                parent_key = "#{self.class.config_name}:#{identifier}"
                index_key = "#{parent_key}:#{index_name}:#{field_value}"

                # Get first member from sorted set
                object_ids = dbclient.zrange(index_key, 0, 0)
                return nil if object_ids.empty?

                indexed_class.new(object_ids.first)
              end

              # Generate bulk finder method (e.g., company.find_all_by_department)
              define_method("find_all_by_#{field}") do |field_value|
                parent_key = "#{self.class.config_name}:#{identifier}"
                index_key = "#{parent_key}:#{index_name}:#{field_value}"

                # Get all members from sorted set
                object_ids = dbclient.zrange(index_key, 0, -1)
                object_ids.map { |id| indexed_class.new(id) }
              end

              # Generate method to get the index for a specific field value
              define_method("#{index_name}_for") do |field_value|
                parent_key = "#{self.class.config_name}:#{identifier}"
                index_key = "#{parent_key}:#{index_name}:#{field_value}"
                Familia::SortedSet.new(nil, dbkey: index_key, logical_database: logical_database)
              end

              # Generate method to rebuild the index for this parent instance
              define_method("rebuild_#{index_name}") do
                # This would need to be implemented based on how you track which
                # objects belong to this parent instance
                # For now, just a placeholder
              end
            end
          end

          # Generate class-level finder methods
          def generate_class_finder_methods(field, index_name)
            # Generate class-level finder method (e.g., Domain.find_by_display_name)
            define_singleton_method("find_by_#{field}") do |field_value|
              index_key = "#{config_name}:#{index_name}"
              object_id = dbclient.hget(index_key, field_value.to_s)

              return nil unless object_id

              new(object_id)
            end

            # Generate class-level bulk finder method
            define_singleton_method("find_all_by_#{field}") do |field_values|
              return [] if field_values.empty?

              index_key = "#{config_name}:#{index_name}"
              object_ids = dbclient.hmget(index_key, *field_values.map(&:to_s))
              # Filter out nil values and instantiate objects
              object_ids.compact.map { |object_id| new(object_id) }
            end

            # Generate method to get the class-level index hash directly
            define_singleton_method(index_name.to_s) do
              index_key = "#{config_name}:#{index_name}"
              Familia::HashKey.new(nil, dbkey: index_key, logical_database: logical_database)
            end

            # Generate method to rebuild the class-level index
            define_singleton_method("rebuild_#{index_name}") do
              index_key = "#{config_name}:#{index_name}"

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
              index_key = "#{self.class.config_name}:#{index_name}"
              field_value = send(field)

              return unless field_value

              dbclient.hset(index_key, field_value.to_s, identifier)
            end

            define_method("remove_from_class_#{index_name}") do
              index_key = "#{self.class.config_name}:#{index_name}"
              field_value = send(field)

              return unless field_value

              dbclient.hdel(index_key, field_value.to_s)
            end

            define_method("update_in_class_#{index_name}") do |old_field_value = nil|
              index_key = "#{self.class.config_name}:#{index_name}"
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
            # Indexes are now scoped to parent instances using SortedSets

            method_name = "add_to_#{context_class_name.downcase}_#{index_name}"
            Familia.ld("[generate_relationship_index_methods] #{name} method #{method_name}")

            define_method(method_name) do |context_instance|
              return unless context_instance

              field_value = send(field)
              return unless field_value

              # Build parent-scoped key: parent_class:parent_id:index_name:field_value
              parent_key = "#{context_instance.class.config_name}:#{context_instance.identifier}"
              index_key = "#{parent_key}:#{index_name}:#{field_value}"

              # Use SortedSet with timestamp score for insertion order
              dbclient.zadd(index_key, Time.now.to_f, identifier)
            end

            method_name = "remove_from_#{context_class_name.downcase}_#{index_name}"
            Familia.ld("[generate_relationship_index_methods] #{name} method #{method_name}")

            define_method(method_name) do |context_instance|
              return unless context_instance

              field_value = send(field)
              return unless field_value

              # Build parent-scoped key
              parent_key = "#{context_instance.class.config_name}:#{context_instance.identifier}"
              index_key = "#{parent_key}:#{index_name}:#{field_value}"

              # Remove from SortedSet
              dbclient.zrem(index_key, identifier)
            end

            method_name = "update_in_#{context_class_name.downcase}_#{index_name}"
            Familia.ld("[generate_relationship_index_methods] #{name} method #{method_name}")

            define_method(method_name) do |context_instance, old_field_value = nil|
              return unless context_instance

              new_field_value = send(field)
              parent_key = "#{context_instance.class.config_name}:#{context_instance.identifier}"

              dbclient.multi do |tx|
                # Remove from old index if provided
                if old_field_value
                  old_index_key = "#{parent_key}:#{index_name}:#{old_field_value}"
                  tx.zrem(old_index_key, identifier)
                end

                # Add to new index if present
                if new_field_value
                  new_index_key = "#{parent_key}:#{index_name}:#{new_field_value}"
                  tx.zadd(new_index_key, Time.now.to_f, identifier)
                end
              end
            end
          end
        end

        # Instance methods for indexed objects
        module InstanceMethods
          # Update all indexes for a given parent context
          # For class-level indexes (class_indexed_by), parent_context should be nil
          # For relationship indexes (indexed_by), parent_context should be the parent instance
          def update_all_indexes(old_values = {}, parent_context = nil)
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
                # Relationship index (indexed_by with parent:) - requires parent context
                next unless parent_context

                # Use snake_case for method naming
                context_class_snake = config[:context_class].name.snake_case
                send("update_in_#{context_class_snake}_#{index_name}", parent_context, old_field_value)
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
              context_class = config[:context_class]

              # Determine which remove method to call
              if context_class == self.class
                # Class-level index (class_indexed_by)
                send("remove_from_class_#{index_name}")
              else
                # Relationship index (indexed_by with parent:) - requires parent context
                next unless parent_context

                # Use snake_case for method naming
                context_class_snake = config[:context_class].name.snake_case
                send("remove_from_#{context_class_snake}_#{index_name}", parent_context)
              end
            end
          end

          # Get all indexes this object appears in
          # Note: For context-scoped indexes, this only shows class-level indexes
          # since context-scoped indexes require a specific context instance
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

              if context_class == self.class
                # Class-level index (class_indexed_by) - check hash key
                index_key = "#{self.class.config_name}:#{index_name}"
                next unless dbclient.hexists(index_key, field_value.to_s)

                memberships << {
                  context_class: 'class',
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: index_key,
                  type: 'class_indexed_by',
                }
              else
                # Context-scoped index (indexed_by) - cannot check without context instance
                # This would require scanning all possible context instances
                memberships << {
                  context_class: config[:context_class_name].snake_case,
                  index_name: index_name,
                  field: field,
                  field_value: field_value,
                  index_key: 'context_dependent',
                  type: 'indexed_by',
                  note: 'Requires context instance for verification',
                }
              end
            end

            memberships
          end

          # Check if this object is indexed in a specific context
          # For class-level indexes, checks the hash key
          # For context-scoped indexes, returns false (requires context instance)
          def indexed_in?(index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel[:index_name] == index_name }
            return false unless config

            field = config[:field]
            field_value = send(field)
            return false unless field_value

            context_class = config[:context_class]

            if context_class == self.class
              # Class-level index (class_indexed_by) - check hash key
              index_key = "#{self.class.config_name}:#{index_name}"
              dbclient.hexists(index_key, field_value.to_s)
            else
              # Context-scoped index (indexed_by) - cannot verify without context instance
              false
            end
          end
        end
      end
    end
  end
end
