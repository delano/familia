# lib/familia/features/relationships/participation.rb

require_relative 'participation_relationship'
require_relative 'collection_operations'
require_relative 'participant_methods'
require_relative 'target_methods'

module Familia
  module Features
    module Relationships
      # Participation module for participates_in relationships using Valkey/Redis collections
      # Provides multi-presence support where objects can exist in multiple collections
      # Integrates both tracking and membership functionality into a single API
      #
      # === Architecture Overview ===
      # This module is organized into clear, separate concerns:
      #
      # 1. CollectionOperations: Shared helpers for all collection manipulation
      # 2. ParticipantMethods: Methods added to the class calling participates_in
      # 3. TargetMethods: Methods added to the target class specified in participates_in
      #
      # This separation makes it crystal clear what methods are added to which class.
      #
      # === Visual Example ===
      # When Domain calls: participates_in Customer, :domains
      #
      # PARTICIPANT (Domain) gets:
      # - domain.in_customer_domains?(customer)
      # - domain.add_to_customer_domains(customer)
      # - domain.remove_from_customer_domains(customer)
      #
      # TARGET (Customer) gets:
      # - customer.domains
      # - customer.add_domain(domain)
      # - customer.remove_domain(domain)
      # - customer.add_domains([...])
      #
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
            participation_relationships << ParticipationRelationship.new(
              target_class: klass_name,
              target_class_name: name || to_s,
              collection_name: collection_name,
              score: score,
              on_destroy: on_destroy,
              type: type,
              bidirectional: bidirectional,
            )

            # STEP 1: Add collection management methods to the class itself
            # e.g., User.all_users, User.add_to_all_users(user)
            TargetMethods::Builder.build_class_level(self, collection_name, type)

            # STEP 2: Add participation methods to instances (if bidirectional)
            # e.g., user.in_class_all_users?, user.add_to_class_all_users
            if bidirectional
              ParticipantMethods::Builder.build(self, 'class', collection_name, type)
            end
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
            # Handle class target using Familia.resolve_class and string refinements
            resolved_class = Familia.resolve_class(target_class)
            target_class_name = resolved_class.name.demodularize

            # Store metadata for this participation relationship
            participation_relationships << ParticipationRelationship.new(
              target_class: target_class,           # as passed to `participates_in`
              target_class_name: target_class_name, # pascalized
              collection_name: collection_name,
              score: score,
              on_destroy: on_destroy,
              type: type,
              bidirectional: bidirectional,
            )

            # Resolve target class if it's a symbol/string
            actual_target_class = if target_class.is_a?(Class)
                                    target_class
                                  else
                                    Familia.member_by_config_name(target_class)
                                  end

            # STEP 1: Add collection management methods to TARGET class (Customer)
            # Customer gets: domains, add_domain, remove_domain, etc.
            TargetMethods::Builder.build(actual_target_class, collection_name, type)

            # STEP 2: Add participation methods to PARTICIPANT class (Domain) - only if bidirectional
            # Domain gets: in_customer_domains?, add_to_customer_domains, etc.
            if bidirectional
              ParticipantMethods::Builder.build(self, target_class_name, collection_name, type)
            end
          end

          # Get all participation relationships for this class
          def participation_relationships
            @participation_relationships ||= []
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
            participation_config = self.class.participation_relationships.find do |details|
              # Normalize both sides for comparison to handle Class, Symbol, and String types
              config_target = details.target_class
              config_target = config_target.name if config_target.is_a?(Class)
              config_target = config_target.to_s

              comparison_target = target_class
              comparison_target = comparison_target.name if comparison_target.is_a?(Class)
              comparison_target = comparison_target.to_s

              config_target == comparison_target && details.collection_name == collection_name
            end

            return current_score unless participation_config

            score_calculator = participation_config.score

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

          # Add participation tracking to reverse index
          def add_participation_membership(collection_key)
            reverse_index_key = "#{dbkey}:participations"
            dbclient.sadd(reverse_index_key, collection_key)
          end

          # Remove participation tracking from reverse index
          def remove_participation_membership(collection_key)
            reverse_index_key = "#{dbkey}:participations"
            dbclient.srem(reverse_index_key, collection_key)
          end

          # Get all collections this object appears in
          #
          # @return [Array<Hash>] Array of collection information
          def participation_memberships
            return [] unless self.class.respond_to?(:participation_relationships)

            # Use reverse index if available, otherwise fall back to scan
            reverse_index_key = "#{dbkey}:participations"
            collection_keys = dbclient.smembers(reverse_index_key)

            if collection_keys.empty?
              # Fall back to scan approach for objects without reverse index
              collection_keys = []
              self.class.participation_relationships.each do |config|
                target_class_name = config.target_class_name
                collection_name = config.collection_name
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
                target_class_name = config.target_class_name
                collection_name = config.collection_name
                type = config.type

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
                rescue Redis::ConnectionError, Redis::TimeoutError => e
                  Familia.ld "[#{key}] Error: #{e.message}"
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

        end
      end
    end
  end
end
