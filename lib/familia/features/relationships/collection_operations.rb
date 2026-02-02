# lib/familia/features/relationships/collection_operations.rb
#
# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      # Shared collection operations for Participation module
      # Provides common methods for working with Horreum-managed DataType collections
      # Used by both ParticipantMethods and TargetMethods to reduce duplication
      module CollectionOperations
        using Familia::Refinements::StylizeWords

        # Ensure a target class has the specified DataType field defined
        # @param target_class [Class] The class that should have the collection
        # @param collection_name [Symbol] Name of the collection field
        # @param type [Symbol] Collection type (:sorted_set, :set, :list)
        def ensure_collection_field(target_class, collection_name, type)
          return if target_class.method_defined?(collection_name)

          target_class.send(type, collection_name)
        end

        # Add an item to a collection, handling type-specific operations
        # @param collection [Familia::DataType] The collection to add to
        # @param item [Object] The item to add (must respond to identifier)
        # @param score [Float, nil] Score for sorted sets
        # @param type [Symbol] Collection type
        def add_to_collection(collection, item, type:, score: nil, target_class: nil, collection_name: nil)
          case type
          when :sorted_set
            # Ensure score is never nil for sorted sets
            score ||= calculate_item_score(item, target_class, collection_name)
            collection.add(item, score)
          when :list
            # Lists use push/unshift operations
            collection.add(item)
          when :set
            # Sets use simple add
            collection.add(item)
          else
            raise ArgumentError, "Unknown collection type: #{type}"
          end
        end

        # Remove an item from a collection
        # @param collection [Familia::DataType] The collection to remove from
        # @param item [Object] The item to remove (must respond to identifier)
        # @param type [Symbol] Collection type
        def remove_from_collection(collection, item, type: nil)
          # All collection types support remove/delete
          collection.remove(item)
        end

        # Check if an item is a member of a collection
        # @param collection [Familia::DataType] The collection to check
        # @param item [Object] The item to check (must respond to identifier)
        # @return [Boolean] True if item is in collection
        def member_of_collection?(collection, item)
          collection.member?(item)
        end

        # Bulk add items to a collection using DataType methods
        # @param collection [Familia::DataType] The collection to add to
        # @param items [Array] Array of items to add
        # @param type [Symbol] Collection type
        def bulk_add_to_collection(collection, items, type:, target_class: nil, collection_name: nil)
          return if items.empty?

          case type
          when :sorted_set
            # Add items one by one for sorted sets to ensure proper scoring
            items.each do |item|
              score = calculate_item_score(item, target_class, collection_name)
              collection.add(item, score)
            end
          when :set, :list
            # For sets and lists, add items one by one using DataType methods
            items.each do |item|
              collection.add(item)
            end
          else
            raise ArgumentError, "Unknown collection type: #{type}"
          end
        end

        private

        # Calculate score for an item
        # @param item [Object] The item to score
        # @param target_class [Class, nil] The target class for participation scoring
        # @param collection_name [Symbol, nil] The collection name for participation scoring
        # @return [Float] The calculated score
        def calculate_item_score(item, target_class = nil, collection_name = nil)
          if item.respond_to?(:calculate_participation_score) && target_class && collection_name
            item.calculate_participation_score(target_class, collection_name)
          elsif item.respond_to?(:current_score)
            item.current_score
          else
            Familia.now.to_f
          end
        end
      end
    end
  end
end
