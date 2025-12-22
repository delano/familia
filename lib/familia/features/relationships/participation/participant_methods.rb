# lib/familia/features/relationships/participation/participant_methods.rb
#
# frozen_string_literal: true

require_relative '../collection_operations'
require_relative 'through_model_operations'

module Familia
  module Features
    module Relationships
      # Methods added to PARTICIPANT classes (the ones calling participates_in)
      # These methods allow participant instances to manage their membership in target collections
      #
      # Example: When Domain calls `participates_in Employee, :domains`
      # Domain instances get methods to check/manage their presence in Employee collections
      module ParticipantMethods
        using Familia::Refinements::StylizeWords
        extend CollectionOperations

        # Visual Guide for methods added to PARTICIPANT instances:
        # =========================================================
        # When Domain calls: participates_in Employee, :domains
        #
        # Domain instances (PARTICIPANT) get these methods:
        # ├── in_employee_domains?(employee)              # Check if I'm in this employee's domains
        # ├── add_to_employee_domains(employee, score)    # Add myself to employee's domains
        # ├── remove_from_employee_domains(employee)      # Remove myself from employee's domains
        # ├── score_in_employee_domains(employee)         # Get my score (sorted_set only)
        # └── position_in_employee_domains(employee)      # Get my position (list only)
        #
        # Note: To update scores, use the DataType API directly:
        #   employee.domains.add(domain.identifier, new_score, xx: true)
        #
        module Builder
          extend CollectionOperations

          # Include ThroughModelOperations for through model lifecycle
          extend Participation::ThroughModelOperations

          # Build all participant methods for a participation relationship
          #
          # @param participant_class [Class] The class receiving these methods (e.g., Domain)
          # @param target_class [Class, String] Target class object or 'class' for class-level participation (e.g., Employee or 'class')
          # @param collection_name [Symbol] Name of the collection (e.g., :domains)
          # @param type [Symbol] Collection type (:sorted_set, :set, :list)
          # @param as [Symbol, nil] Optional custom name for relationship methods (e.g., :employees)
          # @param through [Symbol, Class, nil] Through model class for join table pattern
          #
          def self.build(participant_class, target_class, collection_name, type, as, through = nil)
            # Determine target name based on participation context:
            # - Instance-level: target_class is a Class object (e.g., Team) → use config_name ("project_team")
            # - Class-level: target_class is the string 'class' (from class_participates_in) → use as-is
            # The string 'class' is passed from TargetMethods.build_class_add_method when calling
            # calculate_participation_score('class', collection_name) for class-level scoring
            target_name = if target_class.is_a?(String)
              target_class  # 'class' for class-level participation
            else
              target_class.config_name  # snake_case class name for instance-level
            end

            # Core participant methods
            build_membership_check(participant_class, target_name, collection_name, type)
            build_add_to_target(participant_class, target_name, collection_name, type, through)
            build_remove_from_target(participant_class, target_name, collection_name, type, through)

            # Type-specific methods
            case type
            when :sorted_set
              build_score_methods(participant_class, target_name, collection_name)
            when :list
              build_position_method(participant_class, target_name, collection_name)
            end

            # Build reverse collection methods on PARTICIPANT class for instance-level participation
            # Skip for class-level participation because:
            # - Class-level uses class_participates_in (e.g., User.all_users)
            # - Bidirectional methods don't make sense: an individual User can't have "all_users"
            # - Class-level collections are accessed directly on the class (User.all_users)
            return if target_class.is_a?(String)  # 'class' indicates class-level participation

            # If `as` is specified, create a custom method for just this collection
            # Otherwise, add to the default pluralized method that unions all collections
            if as
              # Custom method for just this specific collection
              build_reverse_collection_methods(participant_class, target_class, as, [collection_name])
            else
              # Default pluralized method - will include ALL collections for this target
              build_reverse_collection_methods(participant_class, target_class, nil, nil)
            end
          end

          # Generate reverse collection methods on participant class for bidirectional access
          #
          # Creates methods like:
          # - user.team_instances (returns Array of Team instances)
          # - user.team_ids (returns Array of IDs)
          # - user.team? (returns Boolean)
          # - user.team_count (returns Integer)
          #
          # @param participant_class [Class] The participant class (e.g., User)
          # @param target_class [Class] The target class (e.g., Team)
          # @param custom_name [Symbol, nil] Custom method name override (base name without suffix)
          # @param collection_names [Array<Symbol>, nil] Specific collections to include (nil = all)
          #
          def self.build_reverse_collection_methods(participant_class, target_class, custom_name = nil, collection_names = nil)
            # Determine base method name - either custom or target class config_name
            # e.g., "project_team" or "contracting_org"
            base_name = if custom_name
              custom_name.to_s
            else
              # Use config_name as-is (e.g., "project_team")
              target_class.config_name
            end

            # Store collection names as string array for matching
            collections_filter = collection_names&.map(&:to_s)

            # Generate the main collection method (e.g., user.project_team_instances)
            #
            # Loads actual objects - verifies Redis key existence via load_multi.
            # No caching - load_multi is efficient enough and avoids stale data.
            #
            # @note Error Handling: This method lets database errors bubble up to the
            #   application layer, consistent with Familia's error handling pattern.
            #   Potential failures include:
            #   - Familia::NotConnected - Redis connection unavailable
            #   - Redis::TimeoutError - Operation timed out
            #   - Redis::ConnectionError - Network/connection issues
            #
            #   For production environments, consider wrapping calls in application-level
            #   error handling:
            #
            #   @example Application-level error handling
            #     begin
            #       teams = user.project_team_instances
            #     rescue Familia::PersistenceError => e
            #       # Handle database failure (log, fallback, retry, etc.)
            #       Rails.logger.error("Failed to load teams: #{e.message}")
            #       []  # Return empty array or other fallback
            #     end
            #
            participant_class.define_method("#{base_name}_instances") do
              ids = participating_ids_for_target(target_class, collections_filter)
              # Use load_multi for Horreum objects (stored as Redis hashes)
              target_class.load_multi(ids).compact
            end

            # Generate the IDs-only method (e.g., user.project_team_ids)
            #
            # Shallow - returns IDs from participation index without verifying key existence.
            #
            # @note Database errors (connection, timeout) will bubble up to caller.
            #
            participant_class.define_method("#{base_name}_ids") do
              participating_ids_for_target(target_class, collections_filter)
            end

            # Generate the boolean check method (e.g., user.project_team?)
            #
            # Shallow check - verifies participation index membership, not Redis key existence.
            #
            # @note Database errors (connection, timeout) will bubble up to caller.
            #
            participant_class.define_method("#{base_name}?") do
              participating_in_target?(target_class, collections_filter)
            end

            # Generate the count method (e.g., user.project_team_count)
            #
            # Shallow - counts IDs from participation index without verifying key existence.
            #
            # @note Database errors (connection, timeout) will bubble up to caller.
            #
            participant_class.define_method("#{base_name}_count") do
              participating_ids_for_target(target_class, collections_filter).size
            end
          end

          # Build method to check membership in target's collection
          # Creates: domain.in_customer_domains?(customer)
          def self.build_membership_check(participant_class, target_name, collection_name, _type)
            method_name = "in_#{target_name}_#{collection_name}?"

            participant_class.define_method(method_name) do |target_instance|
              return false unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual creation
              collection = target_instance.send(collection_name)
              ParticipantMethods::Builder.member_of_collection?(collection, self)
            end
          end

          # Build method to add self to target's collection
          # Creates: domain.add_to_customer_domains(customer, score, through_attrs: {})
          def self.build_add_to_target(participant_class, target_name, collection_name, type, through = nil)
            method_name = "add_to_#{target_name}_#{collection_name}"

            participant_class.define_method(method_name) do |target_instance, score = nil, through_attrs: {}|
              return unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual creation
              collection = target_instance.send(collection_name)

              # Calculate score if needed and not provided
              if type == :sorted_set && score.nil?
                score = calculate_participation_score(target_instance.class, collection_name)
              end

              # Resolve through class if specified
              through_class = through ? Familia.resolve_class(through) : nil

              # Use transaction for atomicity between collection add and reverse index tracking
              # All operations use Horreum's DataType methods (not direct Redis calls)
              target_instance.transaction do |_tx|
                # Add to collection using DataType method (ZADD/SADD/RPUSH)
                ParticipantMethods::Builder.add_to_collection(
                  collection,
                  self,
                  score: score,
                  type: type,
                  target_class: target_instance.class,
                  collection_name: collection_name,
                )

                # Track participation for efficient cleanup using DataType method (SADD)
                track_participation_in(collection.dbkey) if respond_to?(:track_participation_in)
              end

              # TRANSACTION BOUNDARY: Through model operations intentionally happen AFTER
              # the transaction block closes. This is a deliberate design decision because:
              #
              # 1. ThroughModelOperations.find_or_create performs load operations that would
              #    return Redis::Future objects inside a transaction, breaking the flow
              # 2. The core participation (collection add + tracking) is atomic within the tx
              # 3. Through model creation is logically separate - if it fails, the participation
              #    itself succeeded and can be cleaned up or retried independently
              #
              # If Familia's transaction handling changes in the future, revisit this boundary.
              through_model = if through_class
                Participation::ThroughModelOperations.find_or_create(
                  through_class: through_class,
                  target: target_instance,
                  participant: self,
                  attrs: through_attrs
                )
              end

              # Return through model if using :through, otherwise self for backward compat
              through_model || self
            end
          end

          # Build method to remove self from target's collection
          # Creates: domain.remove_from_customer_domains(customer)
          def self.build_remove_from_target(participant_class, target_name, collection_name, type, through = nil)
            method_name = "remove_from_#{target_name}_#{collection_name}"

            participant_class.define_method(method_name) do |target_instance|
              return unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual creation
              collection = target_instance.send(collection_name)

              # Resolve through class if specified
              through_class = through ? Familia.resolve_class(through) : nil

              # Use transaction for atomicity between collection remove and reverse index untracking
              # All operations use Horreum's DataType methods (not direct Redis calls)
              target_instance.transaction do |_tx|
                # Remove from collection using DataType method (ZREM/SREM/LREM)
                ParticipantMethods::Builder.remove_from_collection(collection, self, type: type)

                # Remove from participation tracking using DataType method (SREM)
                untrack_participation_in(collection.dbkey) if respond_to?(:untrack_participation_in)
              end

              # TRANSACTION BOUNDARY: Through model destruction intentionally happens AFTER
              # the transaction block. See build_add_to_target for detailed rationale.
              # The core removal is atomic; through model cleanup is a separate operation.
              if through_class
                Participation::ThroughModelOperations.find_and_destroy(
                  through_class: through_class,
                  target: target_instance,
                  participant: self
                )
              end
            end
          end

          # Build score-related methods for sorted sets
          # Creates: domain.score_in_customer_domains(customer)
          #
          # Note: Score updates use DataType API directly:
          #   customer.domains.add(domain.identifier, new_score, xx: true)
          def self.build_score_methods(participant_class, target_name, collection_name)
            # Get score method
            score_method = "score_in_#{target_name}_#{collection_name}"
            participant_class.define_method(score_method) do |target_instance|
              return nil unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual key construction
              collection = target_instance.send(collection_name)
              collection.score(identifier)
            end
          end

          # Build position method for lists
          # Creates: domain.position_in_customer_domains(customer)
          def self.build_position_method(participant_class, target_name, collection_name)
            method_name = "position_in_#{target_name}_#{collection_name}"

            participant_class.define_method(method_name) do |target_instance|
              return nil unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual key construction
              collection = target_instance.send(collection_name)
              # Use DataType method to find position (index in list)
              collection.to_a.index(identifier)
            end
          end
        end
      end
    end
  end
end
