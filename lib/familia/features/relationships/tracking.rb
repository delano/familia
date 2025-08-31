# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      # Tracking module for tracked_in relationships using Redis sorted sets
      # Provides multi-presence support where objects can exist in multiple collections
      module Tracking
        # Class-level tracking configurations
        def self.included(base)
          base.extend ClassMethods
        end

        module ClassMethods
          # Simple singularize method (basic implementation)
          def singularize_word(word)
            word = word.to_s
            # Basic English pluralization rules (simplified)
            if word.end_with?('ies')
              word[0..-4] + 'y'
            elsif word.end_with?('es') && word.length > 3
              word[0..-3]
            elsif word.end_with?('s') && word.length > 1
              word[0..-2]
            else
              word
            end
          end

          # Simple camelize method (basic implementation)
          def camelize_word(word)
            word.to_s.split('_').map(&:capitalize).join
          end

          # Define a tracked_in relationship
          #
          # @param context_class [Class, Symbol] The class that owns the collection
          # @param collection_name [Symbol] Name of the collection
          # @param score [Symbol, Proc, nil] How to calculate the score
          # @param on_destroy [Symbol] What to do when object is destroyed (:remove, :ignore)
          #
          # @example Basic tracking
          #   tracked_in Customer, :domains, score: :created_at
          #
          # @example Multi-presence tracking
          #   tracked_in Customer, :domains, score: -> { permission_encode(created_at, permission_level) }
          #   tracked_in Team, :domains, score: :added_at
          #   tracked_in Organization, :all_domains, score: :created_at
          def tracked_in(context_class, collection_name, score: nil, on_destroy: :remove)
            # Handle special :global context
            if context_class == :global
              context_class_name = 'Global'
            elsif context_class.is_a?(Class)
              class_name = context_class.name
              context_class_name = if class_name.include?('::')
                                     # Extract the last part after the last ::
                                     class_name.split('::').last
                                   else
                                     class_name
                                   end
            # Extract just the class name, handling anonymous classes
            else
              context_class_name = camelize_word(context_class)
            end

            # Store metadata for this tracking relationship
            tracking_relationships << {
              context_class: context_class,
              context_class_name: context_class_name,
              collection_name: collection_name,
              score: score,
              on_destroy: on_destroy
            }

            # Generate class methods on the context class (skip for global)
            if context_class == :global
              generate_global_class_methods(self, collection_name)
            else
              generate_context_class_methods(context_class, collection_name)
            end

            # Generate instance methods on this class
            generate_tracking_instance_methods(context_class_name, collection_name, score)
          end

          # Get all tracking relationships for this class
          def tracking_relationships
            @tracking_relationships ||= []
          end

          private

          # Generate global collection methods (e.g., Domain.global_all_domains)
          def generate_global_class_methods(target_class, collection_name)
            # Generate global collection getter method
            target_class.define_singleton_method("global_#{collection_name}") do
              collection_key = "global:#{collection_name}"
              Familia::SortedSet.new(nil, dbkey: collection_key, logical_database: logical_database)
            end

            # Generate global add method (e.g., Domain.add_to_global_all_domains)
            target_class.define_singleton_method("add_to_#{collection_name}") do |item, score = nil|
              collection = send("global_#{collection_name}")

              # Calculate score if not provided
              score ||= if item.respond_to?(:calculate_tracking_score)
                          item.calculate_tracking_score(:global, collection_name)
                        else
                          item.current_score
                        end

              # Ensure score is never nil
              score = item.current_score if score.nil?

              collection.add(score, item.identifier)
            end

            # Generate global remove method
            target_class.define_singleton_method("remove_from_#{collection_name}") do |item|
              collection = send("global_#{collection_name}")
              collection.delete(item.identifier)
            end
          end

          # Generate methods on the context class (e.g., Customer.domains)
          def generate_context_class_methods(context_class, collection_name)
            # Resolve context class if it's a symbol/string
            actual_context_class = context_class.is_a?(Class) ? context_class : Object.const_get(camelize_word(context_class))

            # Generate collection getter method
            actual_context_class.define_method(collection_name) do
              collection_key = "#{self.class.name.downcase}:#{identifier}:#{collection_name}"
              Familia::SortedSet.new(nil, dbkey: collection_key, logical_database: self.class.logical_database)
            end

            # Generate add method (e.g., Customer#add_domain)
            actual_context_class.define_method("add_#{singularize_word(collection_name)}") do |item, score = nil|
              collection = send(collection_name)

              # Calculate score if not provided
              score ||= if item.respond_to?(:calculate_tracking_score)
                          item.calculate_tracking_score(self.class, collection_name)
                        else
                          item.current_score
                        end

              # Ensure score is never nil
              score = item.current_score if score.nil?

              collection.add(score, item.identifier)
            end

            # Generate remove method (e.g., Customer#remove_domain)
            actual_context_class.define_method("remove_#{singularize_word(collection_name)}") do |item|
              collection = send(collection_name)
              collection.delete(item.identifier)
            end

            # Generate bulk add method (e.g., Customer#add_domains)
            actual_context_class.define_method("add_#{collection_name}") do |items|
              return if items.empty?

              collection = send(collection_name)

              # Prepare batch data
              batch_data = items.map do |item|
                score = if item.respond_to?(:calculate_tracking_score)
                          item.calculate_tracking_score(self.class, collection_name)
                        else
                          item.current_score
                        end
                # Ensure score is never nil
                score = item.current_score if score.nil?
                { member: item.identifier, score: score }
              end

              # Use batch operation from RedisOperations
              collection.dbclient.pipelined do |pipeline|
                batch_data.each do |data|
                  pipeline.zadd(collection.rediskey, data[:score], data[:member])
                end
              end
            end

            # Generate query methods with score filtering
            actual_context_class.define_method("#{collection_name}_with_permission") do |min_permission = :read|
              collection = send(collection_name)
              permission_score = ScoreEncoding.permission_encode(0, min_permission)

              collection.zrangebyscore(permission_score, '+inf', with_scores: true)
            end
          end

          # Generate instance methods on the tracked class
          def generate_tracking_instance_methods(context_class_name, collection_name, _score_calculator)
            # Method to check if this object is in a specific collection
            # e.g., domain.in_customer_domains?(customer)
            define_method("in_#{context_class_name.downcase}_#{collection_name}?") do |context_instance|
              collection_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{collection_name}"
              dbclient.zscore(collection_key, identifier) != nil
            end

            # Method to add this object to a specific collection
            # e.g., domain.add_to_customer_domains(customer, score)
            define_method("add_to_#{context_class_name.downcase}_#{collection_name}") do |context_instance, score = nil|
              collection_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{collection_name}"

              score ||= calculate_tracking_score(context_class_name, collection_name)

              # Ensure score is never nil
              score = current_score if score.nil?

              dbclient.zadd(collection_key, score, identifier)
            end

            # Method to remove this object from a specific collection
            # e.g., domain.remove_from_customer_domains(customer)
            define_method("remove_from_#{context_class_name.downcase}_#{collection_name}") do |context_instance|
              collection_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{collection_name}"
              dbclient.zrem(collection_key, identifier)
            end

            # Method to get score in a specific collection
            # e.g., domain.score_in_customer_domains(customer)
            define_method("score_in_#{context_class_name.downcase}_#{collection_name}") do |context_instance|
              collection_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{collection_name}"
              dbclient.zscore(collection_key, identifier)
            end

            # Method to update score in a specific collection
            # e.g., domain.update_score_in_customer_domains(customer, new_score)
            define_method("update_score_in_#{context_class_name.downcase}_#{collection_name}") do |context_instance, new_score|
              collection_key = "#{context_class_name.downcase}:#{context_instance.identifier}:#{collection_name}"
              dbclient.zadd(collection_key, new_score, identifier, xx: true) # Only update existing
            end
          end
        end

        # Instance methods for tracked objects
        module InstanceMethods
          # Calculate the appropriate score for a tracking relationship
          #
          # @param context_class [Class] The context class (e.g., Customer)
          # @param collection_name [Symbol] The collection name (e.g., :domains)
          # @return [Float] Calculated score
          def calculate_tracking_score(context_class, collection_name)
            # Find the tracking configuration
            tracking_config = self.class.tracking_relationships.find do |config|
              config[:context_class] == context_class && config[:collection_name] == collection_name
            end

            return current_score unless tracking_config

            score_calculator = tracking_config[:score]

            case score_calculator
            when Symbol
              # Field name or method name
              if respond_to?(score_calculator)
                value = send(score_calculator)
                if value.respond_to?(:to_f)
                  value.to_f
                elsif value.respond_to?(:to_i)
                  encode_score(value, 0)
                else
                  current_score
                end
              else
                current_score
              end
            when Proc
              # Execute proc in context of this instance
              result = instance_exec(&score_calculator)
              # Ensure we get a numeric result
              if result.nil?
                current_score
              elsif result.respond_to?(:to_f)
                result.to_f
              else
                current_score
              end
            when Numeric
              score_calculator.to_f
            else
              current_score
            end
          end

          # Update presence in all tracked collections atomically
          def update_all_tracking_collections
            return unless self.class.respond_to?(:tracking_relationships)

            []

            self.class.tracking_relationships.each do |config|
              config[:context_class_name]
              config[:collection_name]

              # This is a simplified version - in practice, you'd need to know
              # which specific instances this object should be tracked in
              # For now, we'll skip the automatic update and rely on explicit calls
            end
          end

          # Remove from all tracking collections (used during destroy)
          def remove_from_all_tracking_collections
            return unless self.class.respond_to?(:tracking_relationships)

            # Get all possible collection keys this object might be in
            # This is expensive but necessary for cleanup
            redis_conn = redis
            pattern = '*:*:*' # This could be optimized with better key patterns

            cursor = 0
            matching_keys = []

            loop do
              cursor, keys = redis_conn.scan(cursor, match: pattern, count: 1000)
              matching_keys.concat(keys)
              break if cursor == 0
            end

            # Filter keys that might contain this object and remove it
            redis_conn.pipelined do |pipeline|
              matching_keys.each do |key|
                # Check if this key matches any of our tracking relationships
                self.class.tracking_relationships.each do |config|
                  context_class_name = config[:context_class_name].downcase
                  collection_name = config[:collection_name]

                  if key.include?(context_class_name) && key.include?(collection_name.to_s)
                    pipeline.zrem(key, identifier)
                  end
                end
              end
            end
          end

          # Get all collections this object appears in
          #
          # @return [Array<Hash>] Array of collection information
          def tracking_collections_membership
            return [] unless self.class.respond_to?(:tracking_relationships)

            memberships = []

            self.class.tracking_relationships.each do |config|
              context_class_name = config[:context_class_name]
              collection_name = config[:collection_name]

              # Find all instances of context_class where this object appears
              # This is simplified - in practice you'd need a more efficient approach
              pattern = "#{context_class_name.downcase}:*:#{collection_name}"

              dbclient.scan_each(match: pattern) do |key|
                score = dbclient.zscore(key, identifier)
                if score
                  context_id = key.split(':')[1]
                  memberships << {
                    context_class: context_class_name,
                    context_id: context_id,
                    collection_name: collection_name,
                    score: score,
                    decoded_score: decode_score(score)
                  }
                end
              end
            end

            memberships
          end
        end

        # Include instance methods when this module is included
        def self.included(base)
          base.include InstanceMethods
          super
        end
      end
    end
  end
end
