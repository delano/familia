# lib/familia/features/relationships/indexing.rb

module Familia
  module Features
    module Relationships
      # Indexing module for indexed_by relationships using Redis hashes
      # Provides O(1) lookups for finding objects by field values
      module Indexing
        # Class-level indexing configurations
        def self.included(base)
          base.extend ClassMethods
          base.include InstanceMethods
          super
        end

        module ClassMethods
          # Define an indexed_by relationship for fast lookups
          #
          # @param field [Symbol] The field to index on
          # @param context [Class, Symbol] The context class that owns the index
          # @param index_name [Symbol] Name of the index hash
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Basic indexing
          #   indexed_by :display_name, context: Customer, index_name: :domain_index
          #
          # @example Global indexing
          #   indexed_by :domain_id, context: :global, index_name: :domain_lookup
          def indexed_by(field, index_name, parent:, finder: true)
            # Validate that we're not using :global parent (use class_indexed_by instead)
            if parent == :global
              raise ArgumentError, "Use class_indexed_by for global indexes instead of indexed_by with parent: :global"
            end

            context_class = parent
            context_class_name = if context_class.is_a?(Class)
                                   context_class.name
                                 else
                                   context_class.to_s.camelize
                                 end

            # Store metadata for this indexing relationship
            indexing_relationships << {
              field: field,
              context_class: context_class,
              context_class_name: context_class_name,
              index_name: index_name,
              finder: finder
            }

            # Generate finder methods on the context class
            generate_context_finder_methods(context_class, field, index_name) if finder

            # Generate instance methods for maintaining the index
            generate_indexing_instance_methods(context_class_name, field, index_name)
          end

          # Define a global/class-level indexed lookup
          #
          # @param field [Symbol] The field to index on
          # @param index_name [Symbol] Name of the index hash
          # @param finder [Boolean] Whether to generate finder methods
          #
          # @example Global indexing (following class_ prefix convention)
          #   class_indexed_by :email, :email_lookup
          #   class_indexed_by :username, :username_lookup, finder: false
          def class_indexed_by(field, index_name, finder: true)
            # Store metadata for this indexing relationship
            indexing_relationships << {
              field: field,
              context_class: :global,
              context_class_name: 'global',
              index_name: index_name,
              finder: finder
            }

            # Generate global finder methods if requested
            generate_global_finder_methods(field, index_name) if finder

            # Generate instance methods for maintaining the global index
            generate_indexing_instance_methods('global', field, index_name)
          end

          # Get all indexing relationships for this class
          def indexing_relationships
            @indexing_relationships ||= []
          end

          private

          # Generate finder methods on the context class (e.g., Customer.find_by_display_name)
          def generate_context_finder_methods(context_class, field, index_name)
            # Resolve context class if it's a symbol/string
            actual_context_class = context_class.is_a?(Class) ? context_class : Object.const_get(context_class.to_s.camelize)

            # Generate finder method (e.g., Customer.find_by_display_name)
            actual_context_class.define_method("find_by_#{field}") do |field_value|
              index_key = "#{self.class.name.downcase}:#{identifier}:#{index_name}"
              object_id = dbclient.hget(index_key, field_value.to_s)

              return nil unless object_id

              # Find the indexed class and instantiate the object
              indexed_class = nil
              self.class.const_get(:INDEXED_CLASSES, false)&.each do |klass|
                if klass.indexing_relationships.any? { |rel| rel[:index_name] == index_name }
                  indexed_class = klass
                  break
                end
              end

              indexed_class&.new(identifier: object_id)
            end

            # Generate bulk finder method (e.g., Customer.find_all_by_display_name)
            actual_context_class.define_method("find_all_by_#{field}") do |field_values|
              return [] if field_values.empty?

              index_key = "#{self.class.name.downcase}:#{identifier}:#{index_name}"
              object_ids = dbclient.hmget(index_key, *field_values.map(&:to_s))

              # Filter out nil values and instantiate objects
              found_objects = object_ids.compact.filter_map do |object_id|
                # Find the indexed class and instantiate the object
                indexed_class = nil
                self.class.const_get(:INDEXED_CLASSES, false)&.each do |klass|
                  if klass.indexing_relationships.any? { |rel| rel[:index_name] == index_name }
                    indexed_class = klass
                    break
                  end
                end

                indexed_class&.new(identifier: object_id)
              end

              found_objects
            end

            # Generate method to get the index hash directly
            actual_context_class.define_method(index_name) do
              index_key = "#{self.class.name.downcase}:#{identifier}:#{index_name}"
              Familia::HashKey.new(nil, dbkey: index_key, logical_database: self.class.logical_database)
            end

            # Generate method to rebuild the index
            actual_context_class.define_method("rebuild_#{index_name}") do
              index_key = "#{self.class.name.downcase}:#{identifier}:#{index_name}"

              # Clear existing index
              dbclient.del(index_key)

              # This is a simplified version - in practice, you'd need to iterate
              # through all objects that should be in this index
              # Implementation would depend on how you track which objects belong to this context
            end
          end

          # Generate global finder methods (when context is :global)
          def generate_global_finder_methods(field, index_name)
            # Generate global finder method (e.g., Domain.find_by_display_name_globally)
            define_method("find_by_#{field}_globally") do |field_value|
              index_key = "global:#{index_name}"
              object_id = dbclient.hget(index_key, field_value.to_s)

              return nil unless object_id

              new(identifier: object_id)
            end

            # Generate global bulk finder method
            define_method("find_all_by_#{field}_globally") do |field_values|
              return [] if field_values.empty?

              index_key = "global:#{index_name}"
              object_ids = dbclient.hmget(index_key, *field_values.map(&:to_s))

              # Filter out nil values and instantiate objects
              object_ids.compact.map { |object_id| new(identifier: object_id) }
            end

            # Generate method to get the global index hash directly
            define_method("global_#{index_name}") do
              index_key = "global:#{index_name}"
              Familia::HashKey.new(nil, dbkey: index_key, logical_database: logical_database)
            end

            # Generate method to rebuild the global index
            define_method("rebuild_global_#{index_name}") do
              index_key = "global:#{index_name}"

              # Clear existing index
              dbclient.del(index_key)

              # Rebuild from all existing objects
              # This would need to scan through all objects of this class
              # Implementation depends on how objects are stored/tracked
            end
          end

          # Generate instance methods for maintaining indexes
          def generate_indexing_instance_methods(context_class_name, field, index_name)
            # Method to add this object to a specific index
            # e.g., domain.add_to_customer_domain_index(customer)
            if context_class_name == 'global'
              # Global index methods
              define_method("add_to_global_#{index_name}") do
                index_key = "global:#{index_name}"
                field_value = send(field)

                return unless field_value

                dbclient.hset(index_key, field_value.to_s, identifier)
              end

              define_method("remove_from_global_#{index_name}") do
                index_key = "global:#{index_name}"
                field_value = send(field)

                return unless field_value

                dbclient.hdel(index_key, field_value.to_s)
              end

              define_method("update_in_global_#{index_name}") do |old_field_value = nil|
                index_key = "global:#{index_name}"
                new_field_value = send(field)

                dbclient.multi do |tx|
                  # Remove old value if provided
                  tx.hdel(index_key, old_field_value.to_s) if old_field_value

                  # Add new value if present
                  tx.hset(index_key, new_field_value.to_s, identifier) if new_field_value
                end
              end
            else
              define_method("add_to_#{context_class_name.downcase}_#{index_name}") do |context_instance|
                index_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{index_name}"
                field_value = send(field)

                return unless field_value

                dbclient.hset(index_key, field_value.to_s, identifier)
              end

              # Method to remove this object from a specific index
              define_method("remove_from_#{context_class_name.downcase}_#{index_name}") do |context_instance|
                index_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{index_name}"
                field_value = send(field)

                return unless field_value

                dbclient.hdel(index_key, field_value.to_s)
              end

              # Method to update this object in a specific index (handles field value changes)
              define_method("update_in_#{context_class_name.downcase}_#{index_name}") do |context_instance, old_field_value = nil|
                index_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{index_name}"
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
        end

        # Instance methods for indexed objects
        module InstanceMethods
          # Update all indexes that this object participates in
          def update_all_indexes(old_values = {})
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              field = config[:field]
              context_class_name = config[:context_class_name]
              index_name = config[:index_name]

              old_field_value = old_values[field]

              if context_class_name == 'global'
                send("update_in_global_#{index_name}", old_field_value)
              else
                # For non-global indexes, we'd need to know which context instances
                # this object should be indexed in. This is a simplified approach.
                # In practice, you'd need to track relationships or pass context.
              end
            end
          end

          # Remove from all indexes (used during destroy)
          def remove_from_all_indexes
            return unless self.class.respond_to?(:indexing_relationships)

            self.class.indexing_relationships.each do |config|
              field = config[:field]
              context_class_name = config[:context_class_name]
              index_name = config[:index_name]

              if context_class_name == 'global'
                send("remove_from_global_#{index_name}")
              else
                # For non-global indexes, we'd need to find all context instances
                # that have this object indexed. This is expensive but necessary for cleanup.
                pattern = "#{context_class_name.downcase}:*:#{index_name}"
                field_value = send(field)

                next unless field_value

                dbclient.scan_each(match: pattern) do |key|
                  dbclient.hdel(key, field_value.to_s)
                end
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
              context_class_name = config[:context_class_name]
              index_name = config[:index_name]
              field_value = send(field)

              next unless field_value

              if context_class_name == 'global'
                index_key = "global:#{index_name}"
                if dbclient.hexists(index_key, field_value.to_s)
                  memberships << {
                    context_class: 'global',
                    index_name: index_name,
                    field: field,
                    field_value: field_value,
                    index_key: index_key
                  }
                end
              else
                # Scan for all context instances that have this object indexed
                pattern = "#{context_class_name.downcase}:*:#{index_name}"

                dbclient.scan_each(match: pattern) do |key|
                  if dbclient.hexists(key, field_value.to_s)
                    context_id = key.split(':')[1]
                    memberships << {
                      context_class: context_class_name,
                      context_id: context_id,
                      index_name: index_name,
                      field: field,
                      field_value: field_value,
                      index_key: key
                    }
                  end
                end
              end
            end

            memberships
          end

          # Check if this object is indexed in a specific context
          def indexed_in?(context_instance, index_name)
            return false unless self.class.respond_to?(:indexing_relationships)

            config = self.class.indexing_relationships.find { |rel| rel[:index_name] == index_name }
            return false unless config

            field = config[:field]
            field_value = send(field)
            return false unless field_value

            if config[:context_class_name] == 'global'
              index_key = "global:#{index_name}"
            else
              context_class_name = config[:context_class_name]
              index_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{index_name}"
            end

            dbclient.hexists(index_key, field_value.to_s)
          end
        end
      end
    end
  end
end
