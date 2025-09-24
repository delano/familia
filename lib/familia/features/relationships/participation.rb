# lib/familia/features/relationships/participation.rb

module Familia
  module Features
    module Relationships
      # Participation module for participates_in relationships using Valkey/Redis collections
      # Provides multi-presence support where objects can exist in multiple collections
      # Integrates both tracking and membership functionality into a single API
      module Participation
        using Familia::Refinements::StylizeWords

        # Class-level participation configurations
        def self.included(base)
          base.extend ModelClassMethods
          base.include ModelInstanceMethods
          super
        end

        # Participation::ModelClassMethods
        #
        module ModelClassMethods
          # Define a class-level participation collection
          #
          # @param collection_name [Symbol] Name of the class-level collection
          # @param score [Symbol, Proc, nil] How to calculate the score
          # @param on_destroy [Symbol] What to do when object is destroyed (:remove, :ignore)
          # @param type [Symbol] Type of Valkey/Redis collection (:sorted_set, :set, :list)
          # @param bidirectional [Boolean] Whether to generate convenience methods
          #
          # @example Class-level participation
          #   class_participates_in :all_customers, score: :created_at
          #   class_participates_in :active_users, score: -> { status == 'active' ? Familia.now.to_i : 0 }
          def class_participates_in(collection_name, score: nil, on_destroy: :remove,
                                    type: :sorted_set, bidirectional: true)
            klass_name = (name || to_s).downcase

            # Store metadata for this participation relationship
            participation_relationships << {
              target_class: klass_name,
              target_class_name: name || to_s,
              collection_name: collection_name,
              score: score,
              on_destroy: on_destroy,
              type: type,
              bidirectional: bidirectional,
            }

            # Generate class-level collection methods
            generate_participation_class_methods(self, collection_name, type)

            # Generate instance methods for class-level participation
            generate_participation_instance_methods('class', collection_name, score, type) if bidirectional
          end

          # Define a participates_in relationship (previously tracked_in and member_of)
          #
          # @param target_class [Class, Symbol] The class that owns the collection
          # @param collection_name [Symbol] Name of the collection
          # @param score [Symbol, Proc, nil] How to calculate the score
          # @param on_destroy [Symbol] What to do when object is destroyed (:remove, :ignore)
          # @param type [Symbol] Type of Valkey/Redis collection (:sorted_set, :set, :list)
          # @param bidirectional [Boolean] Whether to generate convenience methods on participant
          #
          # @example Basic participation
          #   participates_in Customer, :domains, score: :created_at
          #
          # @example Multi-presence participation with different types
          #   participates_in Customer, :domains, score: -> { permission_encode(created_at, permission_level) }
          #   participates_in Team, :domains, score: :added_at, type: :set
          #   participates_in Organization, :all_domains, score: :created_at, bidirectional: false
          def participates_in(target_class, collection_name, score: nil, on_destroy: :remove,
                              type: :sorted_set, bidirectional: true)
            # Handle class target
            if target_class.is_a?(Class)
              class_name = target_class.name
              target_class_name = if class_name.include?('::')
                                    # Extract the last part after the last ::
                                    class_name.split('::').last
                                  else
                                    class_name
                                  end
            else
              target_class_name = target_class.to_s.pascalize
            end

            # Store metadata for this participation relationship
            participation_relationships << {
              target_class: target_class,
              target_class_name: target_class_name,
              collection_name: collection_name,
              score: score,
              on_destroy: on_destroy,
              type: type,
              bidirectional: bidirectional,
            }

            # Generate target class methods
            generate_target_class_methods(target_class, collection_name, type)

            # Generate instance methods on this class (participant)
            generate_participation_instance_methods(target_class_name, collection_name, score, type) if bidirectional
          end

          # Get all participation relationships for this class
          def participation_relationships
            @participation_relationships ||= []
          end

          private

          # Generate class-level collection methods (e.g., User.all_users)
          def generate_participation_class_methods(target_class, collection_name, type)
            # Generate class-level collection getter method
            target_class.define_singleton_method(collection_name.to_s) do
              collection_key = "#{name.downcase}:#{collection_name}"
              case type
              when :sorted_set
                Familia::SortedSet.new(nil, dbkey: collection_key, logical_database: logical_database)
              when :set
                Familia::UnsortedSet.new(nil, dbkey: collection_key, logical_database: logical_database)
              when :list
                Familia::List.new(nil, dbkey: collection_key, logical_database: logical_database)
              end
            end

            # Generate class-level add method (e.g., User.add_to_all_users)
            target_class.define_singleton_method("add_to_#{collection_name}") do |item, score = nil|
              collection = send(collection_name.to_s)

              case type
              when :sorted_set
                # Calculate score if not provided
                score ||= if item.respond_to?(:calculate_participation_score)
                            item.calculate_participation_score('class', collection_name)
                          else
                            item.current_score
                          end

                # Ensure score is never nil
                score = item.current_score if score.nil?

                collection.add(score, item.identifier)
              when :set
                collection.add(item.identifier)
              when :list
                collection.push(item.identifier)
              end
            end

            # Generate class-level remove method
            target_class.define_singleton_method("remove_from_#{collection_name}") do |item|
              collection = send(collection_name.to_s)
              collection.delete(item.identifier)
            end
          end

          # Generate methods on the target class (e.g., Customer.domains)
          def generate_target_class_methods(target_class, collection_name, type)
            # Resolve target class if it's a symbol/string
            actual_target_class = if target_class.is_a?(Class)
                                    target_class
                                  else
                                    # NOTE: This only works if the model class is in the
                                    # top, main namspace. e.g. model_name -> ModelName
                                    # and not Models::ModelName.
                                    Familia.member_by_config_name(target_class)
                                  end

            generate_collection_getter(actual_target_class, collection_name, type)
            generate_add_method(actual_target_class, collection_name, type)
            generate_remove_method(actual_target_class, collection_name)
            generate_bulk_add_method(actual_target_class, collection_name, type)
            generate_permission_query(actual_target_class, collection_name, type)
          end

          def generate_collection_getter(actual_target_class, collection_name, type)
            # Generate collection getter method
            actual_target_class.define_method(collection_name) do
              collection_key = "#{self.class.name.downcase}:#{identifier}:#{collection_name}"
              case type
              when :sorted_set
                Familia::SortedSet.new(nil, dbkey: collection_key,
                                       logical_database: self.class.logical_database)
              when :set
                Familia::UnsortedSet.new(nil, dbkey: collection_key,
                                         logical_database: self.class.logical_database)
              when :list
                Familia::List.new(nil, dbkey: collection_key,
                                  logical_database: self.class.logical_database)
              end
            end
          end

          def generate_add_method(actual_target_class, collection_name, type)
            # Generate add method (e.g., Customer#add_domain)
            actual_target_class.define_method("add_#{collection_name.to_s.singularize}") do |item, score = nil|
              collection = send(collection_name)

              case type
              when :sorted_set
                # Calculate score if not provided
                score ||= if item.respond_to?(:calculate_participation_score)
                            item.calculate_participation_score(self.class, collection_name)
                          else
                            item.current_score
                          end

                # Ensure score is never nil
                score = item.current_score if score.nil?

                collection.add(score, item.identifier)
              when :set
                collection.add(item.identifier)
              when :list
                collection.push(item.identifier)
              end

              # Track participation in reverse index for efficient cleanup
              return unless item.respond_to?(:add_participation_tracking)

              item.add_participation_tracking(collection.dbkey)
            end
          end

          def generate_remove_method(actual_target_class, collection_name)
            # Generate remove method (e.g., Customer#remove_domain)
            actual_target_class.define_method("remove_#{collection_name.to_s.singularize}") do |item|
              collection = send(collection_name)

              # Use appropriate removal method based on collection type
              if collection.is_a?(Familia::SortedSet)
                collection.remove(item.identifier)
              else
                collection.delete(item.identifier)
              end

              # Remove participation tracking
              return unless item.respond_to?(:remove_participation_tracking)

              item.remove_participation_tracking(collection.dbkey)
            end
          end

          def generate_bulk_add_method(actual_target_class, collection_name, type)
            # Generate bulk add method (e.g., Customer#add_domains)
            actual_target_class.define_method("add_#{collection_name}") do |items|
              return if items.empty?

              collection = send(collection_name)
              send("bulk_add_#{type}_items", collection, items)
            end
          end

          def generate_permission_query(actual_target_class, collection_name, type)
            return unless type == :sorted_set

            # Generate query methods with score filtering (for sorted sets)
            actual_target_class.define_method("#{collection_name}_with_permission") do |min_permission = :read|
              collection = send(collection_name)
              permission_score = ScoreEncoding.permission_encode(0, min_permission)

              collection.zrangebyscore(permission_score, '+inf', with_scores: true)
            end
          end

          # Generate instance methods on the participant class
          def generate_participation_instance_methods(target_class_name, collection_name, _score_calculator, type)
            generate_membership_check(target_class_name, collection_name, type)
            generate_add_to_collection(target_class_name, collection_name, type)
            generate_remove_from_collection(target_class_name, collection_name, type)
            generate_score_methods(target_class_name, collection_name, type)
            generate_position_method(target_class_name, collection_name, type)
          end

          def generate_membership_check(target_class_name, collection_name, type)
            # Method to check if this object is in a specific collection
            # e.g., domain.in_customer_domains?(customer)
            define_method("in_#{target_class_name.downcase}_#{collection_name}?") do |target_instance|
              collection_key = "#{target_class_name.downcase}:#{target_instance.identifier}:#{collection_name}"
              case type
              when :sorted_set
                !dbclient.zscore(collection_key, identifier).nil?
              when :set
                dbclient.sismember(collection_key, identifier)
              when :list
                !dbclient.lpos(collection_key, identifier).nil?
              end
            end
          end

          def generate_add_to_collection(target_class_name, collection_name, type)
            # Method to add this object to a specific collection
            # e.g., domain.add_to_customer_domains(customer, score)
            define_method("add_to_#{target_class_name.downcase}_#{collection_name}") do |target_instance, score = nil|
              collection_key = "#{target_class_name.downcase}:#{target_instance.identifier}:#{collection_name}"

              case type
              when :sorted_set
                score ||= calculate_participation_score(target_class_name, collection_name)

                # Ensure score is never nil
                score = current_score if score.nil?

                dbclient.zadd(collection_key, score, identifier)
              when :set
                dbclient.sadd(collection_key, identifier)
              when :list
                dbclient.lpush(collection_key, identifier)
              end
            end
          end

          def generate_remove_from_collection(target_class_name, collection_name, type)
            # Method to remove this object from a specific collection
            # e.g., domain.remove_from_customer_domains(customer)
            define_method("remove_from_#{target_class_name.downcase}_#{collection_name}") do |target_instance|
              collection_key = "#{target_class_name.downcase}:#{target_instance.identifier}:#{collection_name}"
              case type
              when :sorted_set
                dbclient.zrem(collection_key, identifier)
              when :set
                dbclient.srem(collection_key, identifier)
              when :list
                dbclient.lrem(collection_key, 0, identifier) # Remove all occurrences
              end
            end
          end

          def generate_score_methods(target_class_name, collection_name, type)
            return unless type == :sorted_set

            # Method to get score in a specific collection (for sorted sets)
            # e.g., domain.score_in_customer_domains(customer)
            define_method("score_in_#{target_class_name.downcase}_#{collection_name}") do |target_instance|
              collection_key = "#{target_class_name.downcase}:#{target_instance.identifier}:#{collection_name}"
              dbclient.zscore(collection_key, identifier)
            end

            # Method to update score in a specific collection
            # e.g., domain.update_score_in_customer_domains(customer, new_score)
            define_method("update_score_in_#{target_class_name.downcase}_#{collection_name}") do |target_instance,
                                                                                                new_score|
              collection_key = "#{target_class_name.downcase}:#{target_instance.identifier}:#{collection_name}"
              dbclient.zadd(collection_key, new_score, identifier, xx: true) # Only update existing
            end
          end

          def generate_position_method(target_class_name, collection_name, type)
            return unless type == :list

            # Method to get position in a specific collection (for lists)
            define_method("position_in_#{target_class_name.downcase}_#{collection_name}") do |target_instance|
              collection_key = "#{target_class_name.downcase}:#{target_instance.identifier}:#{collection_name}"
              dbclient.lpos(collection_key, identifier)
            end
          end
        end

        # Instance methods for participating objects
        module ModelInstanceMethods
          # Calculate the appropriate score for a participation relationship based on configured scoring strategy
          #
          # This method serves as the single source of truth for participation scoring, supporting multiple
          # scoring strategies defined in relationship configurations. It's called during relationship
          # addition, object creation/save callbacks, field updates, and score maintenance operations.
          #
          # Scoring Strategies:
          # * Symbol - Field name or method name (e.g., :priority_level, :created_at)
          # * Proc - Dynamic calculation executed in instance context (e.g., -> { tenure + performance })
          # * Numeric - Static score applied to all instances (e.g., 100.0)
          # * Fallback - Returns current_score for unrecognized types or missing configs
          #
          # Type Safety:
          # * Robust type normalization handles Class/Symbol/String target class variations
          # * Nil-safe evaluation with multiple fallback layers
          # * Automatic numeric conversion (to_f for floats, encode_score for integers)
          #
          # Usage Examples:
          #   # Field-based scoring
          #   participates_in Organization, :members, score: :priority_level
          #
          #   # Time-based scoring
          #   participates_in Blog, :posts, score: :published_at
          #
          #   # Complex business logic
          #   participates_in Project, :contributors, score: -> { contributions.count * 10 }
          #
          #   # Priority-based Scoring
          #   class Task < Familia::Horreum
          #     field :priority  # 1=low, 5=high
          #     participates_in Project, :tasks, score: :priority
          #   end
          #   task.priority = 5                 # when priority changes
          #   task.add_to_project_tasks(project)
          #
          #   # Complex business logic (sales employee changes departments)
          #   class Employee < Familia::Horreum
          #     field :hire_date
          #     field :performance_rating
          #     participates_in Department, :members, score: -> {
          #       tenure_months = (Time.now - hire_date) / 1.month
          #       base_score = tenure_months * 10
          #       performance_bonus = performance_rating * 100
          #       base_score + performance_bonus
          #     }
          #   end
          #   employee.add_to_department_members(new_department)
          #
          # @param target_class [Class, Symbol, String] The target class containing the collection
          # @param collection_name [Symbol] The collection name within the target class
          # @return [Float] Calculated score for sorted set positioning, falls back to current_score
          def calculate_participation_score(target_class, collection_name)
            # Find the participation configuration with robust type comparison
            participation_config = self.class.participation_relationships.find do |config|
              # Normalize both sides for comparison to handle Class, Symbol, and String types
              config_target = config[:target_class]
              config_target = config_target.name if config_target.is_a?(Class)
              config_target = config_target.to_s

              comparison_target = target_class
              comparison_target = comparison_target.name if comparison_target.is_a?(Class)
              comparison_target = comparison_target.to_s

              config_target == comparison_target && config[:collection_name] == collection_name
            end

            return current_score unless participation_config

            score_calculator = participation_config[:score]

            # Get the raw result based on calculator type
            result = case score_calculator
                     when Symbol
                       # Field name or method name
                       respond_to?(score_calculator) ? send(score_calculator) : nil
                     when Proc
                       # Execute proc in context of this instance
                       instance_exec(&score_calculator)
                     when Numeric
                       # Static numeric value
                       return score_calculator.to_f
                     else
                       # Unrecognized type
                       return current_score
                     end

            # Convert result to appropriate score with unified logic
            convert_to_score(result)
          end

          # Update presence in all participation collections atomically
          def update_all_participation_collections
            return unless self.class.respond_to?(:participation_relationships)

            []

            self.class.participation_relationships.each do |config|
              config[:target_class_name]
              config[:collection_name]

              # This is a simplified version - in practice, you'd need to know
              # which specific instances this object should be participating in
              # For now, we'll skip the automatic update and rely on explicit calls
            end
          end

          private

          # Convert a raw value to an appropriate participation score
          #
          # @param value [Object] The raw value to convert
          # @return [Float] Converted score, falls back to current_score
          def convert_to_score(value)
            return current_score if value.nil?

            if value.respond_to?(:to_f)
              value.to_f
            elsif value.respond_to?(:to_i)
              encode_score(value, 0)
            else
              current_score
            end
          end

          public

          # Update presence in all participation collections atomically
          def update_all_participation_collections
            return unless self.class.respond_to?(:participation_relationships)

            []

            self.class.participation_relationships.each do |config|
              config[:target_class_name]
              config[:collection_name]

              # This is a simplified version - in practice, you'd need to know
              # which specific instances this object should be participating in
              # For now, we'll skip the automatic update and rely on explicit calls
            end
          end

          # Add to class-level participation collections automatically
          def add_to_class_participation_collections
            return unless self.class.respond_to?(:participation_relationships)

            self.class.participation_relationships.each do |config|
              target_class_name = config[:target_class_name]
              collection_name = config[:collection_name]

              # Only auto-add to class-level collections (where target_class matches self.class)
              if target_class_name.downcase == self.class.name.downcase
                # Call the class method to add this object
                self.class.send("add_to_#{collection_name}", self)
              end
            end
          end

          # Add participation tracking to reverse index
          def add_participation_tracking(collection_key)
            reverse_index_key = "#{dbkey}:participations"
            dbclient.sadd(reverse_index_key, collection_key)
          end

          # Remove participation tracking from reverse index
          def remove_participation_tracking(collection_key)
            reverse_index_key = "#{dbkey}:participations"
            dbclient.srem(reverse_index_key, collection_key)
          end

          # Remove from all participation collections (used during destroy)
          # Uses reverse index for efficient cleanup instead of database scan
          def remove_from_all_participation_collections
            return unless self.class.respond_to?(:participation_relationships)

            reverse_index_key = "#{dbkey}:participations"
            collection_keys = dbclient.smembers(reverse_index_key)

            return if collection_keys.empty?

            # Remove from all tracked collections in a single pipeline
            dbclient.pipelined do |pipeline|
              collection_keys.each do |key|
                # Determine collection type from key structure and remove appropriately
                self.class.participation_relationships.each do |config|
                  target_class_name = config[:target_class_name].downcase
                  collection_name = config[:collection_name]
                  type = config[:type]

                  next unless key.include?(target_class_name) && key.include?(collection_name.to_s)

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

              # Clean up the reverse index itself
              pipeline.del(reverse_index_key)
            end
          end

          # Get all collections this object appears in
          #
          # @return [Array<Hash>] Array of collection information
          def participation_collections_membership
            return [] unless self.class.respond_to?(:participation_relationships)

            # Use reverse index if available, otherwise fall back to scan
            reverse_index_key = "#{dbkey}:participations"
            collection_keys = dbclient.smembers(reverse_index_key)

            if collection_keys.empty?
              # Fall back to scan approach for objects without reverse index
              collection_keys = []
              self.class.participation_relationships.each do |config|
                target_class_name = config[:target_class_name]
                collection_name = config[:collection_name]
                pattern = "#{target_class_name.downcase}:*:#{collection_name}"

                dbclient.scan_each(match: pattern) do |key|
                  collection_keys << key
                end
              end
            end

            return [] if collection_keys.empty?

            memberships = []

            # Group keys by type to optimize pipeline operations
            keys_by_type = {}
            collection_keys.each do |key|
              self.class.participation_relationships.each do |config|
                target_class_name = config[:target_class_name]
                collection_name = config[:collection_name]
                type = config[:type]

                next unless key.include?(target_class_name.downcase) && key.include?(collection_name.to_s)

                keys_by_type[type] ||= []
                keys_by_type[type] << {
                  key: key,
                  target_class_name: target_class_name,
                  collection_name: collection_name,
                  type: type,
                }
              end
            end

            # Use pipelined requests to batch all membership checks
            results = {}
            dbclient.pipelined do |pipeline|
              keys_by_type.each do |type, key_configs|
                key_configs.each do |config|
                  key = config[:key]
                  case type
                  when :sorted_set
                    results[key] = pipeline.zscore(key, identifier)
                  when :set
                    results[key] = pipeline.sismember(key, identifier)
                  when :list
                    results[key] = pipeline.lpos(key, identifier)
                  end
                end
              end
            end

            # Process results and build membership array
            keys_by_type.each do |type, key_configs|
              key_configs.each do |config|
                key = config[:key]
                result = begin
                  results[key].value
                rescue StandardError
                  nil
                end

                next unless result

                target_id = key.split(':')[1]
                membership_data = {
                  target_class: config[:target_class_name],
                  target_id: target_id,
                  collection_name: config[:collection_name],
                  type: type,
                }

                case type
                when :sorted_set
                  next unless result # score must be present

                  membership_data[:score] = result
                  membership_data[:decoded_score] = decode_score(result)
                when :set
                  next unless result # must be a member
                when :list
                  next unless result # position must be found

                  membership_data[:position] = result
                end

                memberships << membership_data
              end
            end

            memberships
          end
        end
      end
    end
  end
end
