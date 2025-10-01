# lib/familia/features/relationships/participation/participant_methods.rb

require_relative '../collection_operations'

module Familia
  module Features
    module Relationships
      # Methods added to PARTICIPANT classes (the ones calling participates_in)
      # These methods allow participant instances to manage their membership in target collections
      #
      # Example: When Domain calls `participates_in Customer, :domains`
      # Domain instances get methods to check/manage their presence in Customer collections
      module ParticipantMethods
        using Familia::Refinements::StylizeWords
        extend CollectionOperations

        # Visual Guide for methods added to PARTICIPANT instances:
        # =========================================================
        # When Domain calls: participates_in Customer, :domains
        #
        # Domain instances (PARTICIPANT) get these methods:
        # ├── in_customer_domains?(customer)              # Check if I'm in this customer's domains
        # ├── add_to_customer_domains(customer, score)    # Add myself to customer's domains
        # ├── remove_from_customer_domains(customer)      # Remove myself from customer's domains
        # ├── score_in_customer_domains(customer)         # Get my score (sorted_set only)
        # ├── update_score_in_customer_domains(customer)  # Update my score (sorted_set only)
        # └── position_in_customer_domains(customer)      # Get my position (list only)

        module Builder
          extend CollectionOperations

          # Build all participant methods for a participation relationship
          # @param participant_class [Class] The class receiving these methods (e.g., Domain)
          # @param target_class_name [String] Name of the target class (e.g., "Customer")
          # @param collection_name [Symbol] Name of the collection (e.g., :domains)
          # @param type [Symbol] Collection type (:sorted_set, :set, :list)
          def self.build(participant_class, target_class_name, collection_name, type)
            # Convert to snake_case once for consistency (target_class_name is PascalCase)
            target_name = target_class_name.to_s.snake_case

            # Core participant methods
            build_membership_check(participant_class, target_name, collection_name, type)
            build_add_to_target(participant_class, target_name, collection_name, type)
            build_remove_from_target(participant_class, target_name, collection_name, type)

            # Type-specific methods
            case type
            when :sorted_set
              build_score_methods(participant_class, target_name, collection_name)
            when :list
              build_position_method(participant_class, target_name, collection_name)
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
          # Creates: domain.add_to_customer_domains(customer, score)
          def self.build_add_to_target(participant_class, target_name, collection_name, type)
            method_name = "add_to_#{target_name}_#{collection_name}"

            participant_class.define_method(method_name) do |target_instance, score = nil|
              return unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual creation
              collection = target_instance.send(collection_name)

              # Calculate score if needed and not provided
              if type == :sorted_set && score.nil?
                score = calculate_participation_score(target_instance.class, collection_name)
              end

              ParticipantMethods::Builder.add_to_collection(
                collection,
                self,
                score: score,
                type: type,
                target_class: target_instance.class,
                collection_name: collection_name,
              )

              # Track participation for efficient cleanup
              track_participation_in(collection.dbkey) if respond_to?(:track_participation_in)
            end
          end

          # Build method to remove self from target's collection
          # Creates: domain.remove_from_customer_domains(customer)
          def self.build_remove_from_target(participant_class, target_name, collection_name, type)
            method_name = "remove_from_#{target_name}_#{collection_name}"

            participant_class.define_method(method_name) do |target_instance|
              return unless target_instance&.identifier

              # Use Horreum's DataType accessor instead of manual creation
              collection = target_instance.send(collection_name)

              ParticipantMethods::Builder.remove_from_collection(collection, self, type: type)

              # Remove from participation tracking
              untrack_participation_in(collection.dbkey) if respond_to?(:untrack_participation_in)
            end
          end

          # Build score-related methods for sorted sets
          # Creates: domain.score_in_customer_domains(customer)
          #          domain.update_score_in_customer_domains(customer, new_score)
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
