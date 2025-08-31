# lib/familia/features/relationships/cascading.rb

module Familia
  module Features
    module Relationships
      # Cascading module for handling cascade operations during object lifecycle
      # Supports multi-presence scenarios where objects exist in multiple collections
      module Cascading
        # Cascade strategies
        STRATEGIES = {
          remove: :remove_from_collections,
          ignore: :ignore_collections,
          cascade: :cascade_destroy_dependents
        }.freeze

        # Class-level cascade configurations
        def self.included(base)
          base.extend ClassMethods
          base.include InstanceMethods
          super
        end

        module ClassMethods
          # Get cascade strategies for all relationships
          def cascade_strategies
            strategies = {}

            # Collect strategies from tracking relationships
            if respond_to?(:tracking_relationships)
              tracking_relationships.each do |config|
                key = "#{config[:context_class_name]}.#{config[:collection_name]}"
                strategies[key] = {
                  type: :tracking,
                  strategy: config[:on_destroy] || :remove,
                  config: config
                }
              end
            end

            # Collect strategies from membership relationships
            if respond_to?(:membership_relationships)
              membership_relationships.each do |config|
                key = "#{config[:owner_class_name]}.#{config[:collection_name]}"
                strategies[key] = {
                  type: :membership,
                  strategy: config[:on_destroy] || :remove,
                  config: config
                }
              end
            end

            # Collect strategies from indexing relationships
            if respond_to?(:indexing_relationships)
              indexing_relationships.each do |config|
                key = if config[:context_class_name] == 'global'
                        "global.#{config[:index_name]}"
                      else
                        "#{config[:context_class_name]}.#{config[:index_name]}"
                      end
                strategies[key] = {
                  type: :indexing,
                  strategy: :remove, # Indexes should always be cleaned up
                  config: config
                }
              end
            end

            strategies
          end
        end

        # Instance methods for cascade operations
        module InstanceMethods
          # Execute cascade operations during destroy
          def execute_cascade_operations
            strategies = self.class.cascade_strategies

            # Group operations by strategy for efficient execution
            remove_operations = []
            cascade_operations = []

            strategies.each_value do |strategy_info|
              case strategy_info[:strategy]
              when :remove
                remove_operations << strategy_info
              when :cascade
                cascade_operations << strategy_info
              when :ignore
                # Do nothing
              end
            end

            # Execute remove operations first (cleanup this object's presence)
            execute_remove_operations(remove_operations) if remove_operations.any?

            # Then execute cascade operations (may trigger other destroys)
            execute_cascade_operations_recursive(cascade_operations) if cascade_operations.any?
          end

          # Remove this object from all collections without cascading
          def remove_from_all_collections
            strategies = self.class.cascade_strategies
            remove_operations = strategies.values.reject { |s| s[:strategy] == :ignore }
            execute_remove_operations(remove_operations)
          end

          # Check if destroying this object would trigger cascades
          def cascade_impact
            strategies = self.class.cascade_strategies
            impact = {
              removals: 0,
              cascades: 0,
              affected_collections: [],
              cascade_targets: []
            }

            strategies.each do |key, strategy_info|
              case strategy_info[:strategy]
              when :remove
                impact[:removals] += 1
                impact[:affected_collections] << key
              when :cascade
                impact[:cascades] += 1
                impact[:affected_collections] << key

                # Estimate cascade targets (this is expensive, use carefully)
                targets = estimate_cascade_targets(strategy_info)
                impact[:cascade_targets].concat(targets)
              end
            end

            impact
          end

          private

          # Execute removal operations atomically
          def execute_remove_operations(remove_operations)
            return if remove_operations.empty?

            dbclient.pipelined do |pipeline|
              remove_operations.each do |operation|
                case operation[:type]
                when :tracking
                  remove_from_tracking_collections(pipeline, operation[:config])
                when :membership
                  remove_from_membership_collections(pipeline, operation[:config])
                when :indexing
                  remove_from_indexing_collections(pipeline, operation[:config])
                end
              end
            end
          end

          # Remove from tracking collections
          def remove_from_tracking_collections(pipeline, config)
            context_class_name = config[:context_class_name]
            collection_name = config[:collection_name]

            # Find all collections this object is tracked in
            pattern = "#{context_class_name.downcase}:*:#{collection_name}"

            dbclient.scan_each(match: pattern) do |key|
              pipeline.zrem(key, identifier)
            end
          end

          # Remove from membership collections
          def remove_from_membership_collections(pipeline, config)
            owner_class_name = config[:owner_class_name]
            collection_name = config[:collection_name]
            type = config[:type]

            # Find all collections this object is a member of
            pattern = "#{owner_class_name.downcase}:*:#{collection_name}"

            dbclient.scan_each(match: pattern) do |key|
              case type
              when :sorted_set
                pipeline.zrem(key, identifier)
              when :set
                pipeline.srem(key, identifier)
              when :list
                pipeline.lrem(key, 0, identifier)
              end
            end
          end

          # Remove from indexing collections
          def remove_from_indexing_collections(pipeline, config)
            context_class_name = config[:context_class_name]
            index_name = config[:index_name]
            field = config[:field]

            field_value = send(field) if respond_to?(field)
            return unless field_value

            if context_class_name == 'global'
              index_key = "global:#{index_name}"
              pipeline.hdel(index_key, field_value.to_s)
            else
              # Find all indexes this object appears in
              pattern = "#{context_class_name.downcase}:*:#{index_name}"

              dbclient.scan_each(match: pattern) do |key|
                pipeline.hdel(key, field_value.to_s)
              end
            end
          end

          # Execute cascade operations that may trigger dependent destroys
          def execute_cascade_operations_recursive(cascade_operations)
            cascade_operations.each do |operation|
              case operation[:type]
              when :tracking
                cascade_tracking_dependents(operation[:config])
              when :membership
                cascade_membership_dependents(operation[:config])
              end
            end
          end

          # Cascade destroy for tracking relationships
          def cascade_tracking_dependents(config)
            # This is a complex operation that depends on the specific business logic
            # For now, we'll provide a framework that can be customized

            context_class_name = config[:context_class_name]
            collection_name = config[:collection_name]

            # Find all contexts that track this object
            pattern = "#{context_class_name.downcase}:*:#{collection_name}"

            dbclient.scan_each(match: pattern) do |key|
              # Check if this object is the only member
              if dbclient.zcard(key) == 1 && dbclient.zscore(key, identifier)
                context_id = key.split(':')[1]

                # Optionally destroy the context if it becomes empty
                # This is application-specific logic
                trigger_cascade_callback(:tracking, context_class_name, context_id, collection_name)
              end
            end
          end

          # Cascade destroy for membership relationships
          def cascade_membership_dependents(config)
            # Similar to tracking, this depends on business logic

            owner_class_name = config[:owner_class_name]
            collection_name = config[:collection_name]
            type = config[:type]

            # Find all owners that contain this object
            pattern = "#{owner_class_name.downcase}:*:#{collection_name}"

            dbclient.scan_each(match: pattern) do |key|
              # Check if this object exists in the collection
              is_member = case type
                          when :sorted_set
                            dbclient.zscore(key, identifier) != nil
                          when :set
                            dbclient.sismember(key, identifier)
                          when :list
                            dbclient.lpos(key, identifier) != nil
                          end

              if is_member
                owner_id = key.split(':')[1]
                trigger_cascade_callback(:membership, owner_class_name, owner_id, collection_name)
              end
            end
          end

          # Trigger application-specific cascade callbacks
          def trigger_cascade_callback(relationship_type, class_name, object_id, collection_name)
            # This method can be overridden by applications to implement
            # custom cascade logic

            callback_method = "on_cascade_#{relationship_type}_#{collection_name}"

            return unless respond_to?(callback_method, true)

            send(callback_method, class_name, object_id)
          end

          # Estimate objects that would be affected by cascading (expensive operation)
          def estimate_cascade_targets(strategy_info)
            targets = []

            case strategy_info[:type]
            when :tracking
              config = strategy_info[:config]
              context_class_name = config[:context_class_name]
              collection_name = config[:collection_name]

              pattern = "#{context_class_name.downcase}:*:#{collection_name}"
              dbclient.scan_each(match: pattern) do |key|
                if dbclient.zscore(key, identifier)
                  context_id = key.split(':')[1]
                  targets << {
                    type: :context,
                    class: context_class_name,
                    id: context_id,
                    collection: collection_name
                  }
                end
              end

            when :membership
              config = strategy_info[:config]
              owner_class_name = config[:owner_class_name]
              collection_name = config[:collection_name]
              type = config[:type]

              pattern = "#{owner_class_name.downcase}:*:#{collection_name}"
              dbclient.scan_each(match: pattern) do |key|
                is_member = case type
                            when :sorted_set
                              dbclient.zscore(key, identifier) != nil
                            when :set
                              dbclient.sismember(key, identifier)
                            when :list
                              dbclient.lpos(key, identifier) != nil
                            end

                if is_member
                  owner_id = key.split(':')[1]
                  targets << {
                    type: :owner,
                    class: owner_class_name,
                    id: owner_id,
                    collection: collection_name
                  }
                end
              end
            end

            targets
          end

          # Dry run cascade operations (for testing/preview)
          def cascade_dry_run
            strategies = self.class.cascade_strategies

            preview = {
              removals: [],
              cascades: [],
              affected_keys: []
            }

            strategies.each do |key, strategy_info|
              case strategy_info[:strategy]
              when :remove
                affected_keys = find_affected_keys(strategy_info)
                preview[:removals] << {
                  relationship: key,
                  keys: affected_keys,
                  count: affected_keys.length
                }
                preview[:affected_keys].concat(affected_keys)

              when :cascade
                cascade_targets = estimate_cascade_targets(strategy_info)
                preview[:cascades] << {
                  relationship: key,
                  targets: cascade_targets,
                  count: cascade_targets.length
                }
              end
            end

            preview[:affected_keys].uniq!
            preview
          end

          # Find all Redis keys that would be affected by removing this object
          def find_affected_keys(strategy_info)
            affected_keys = []

            case strategy_info[:type]
            when :tracking
              config = strategy_info[:config]
              context_class_name = config[:context_class_name]
              collection_name = config[:collection_name]
              pattern = "#{context_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                affected_keys << key if dbclient.zscore(key, identifier)
              end

            when :membership
              config = strategy_info[:config]
              owner_class_name = config[:owner_class_name]
              collection_name = config[:collection_name]
              type = config[:type]
              pattern = "#{owner_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                is_member = case type
                            when :sorted_set
                              dbclient.zscore(key, identifier) != nil
                            when :set
                              dbclient.sismember(key, identifier)
                            when :list
                              dbclient.lpos(key, identifier) != nil
                            end
                affected_keys << key if is_member
              end

            when :indexing
              config = strategy_info[:config]
              context_class_name = config[:context_class_name]
              index_name = config[:index_name]
              field = config[:field]

              field_value = send(field) if respond_to?(field)
              if field_value
                if context_class_name == 'global'
                  index_key = "global:#{index_name}"
                  affected_keys << index_key if dbclient.hexists(index_key, field_value.to_s)
                else
                  pattern = "#{context_class_name.downcase}:*:#{index_name}"
                  dbclient.scan_each(match: pattern) do |key|
                    affected_keys << key if dbclient.hexists(key, field_value.to_s)
                  end
                end
              end
            end

            affected_keys
          end
        end

      end
    end
  end
end
