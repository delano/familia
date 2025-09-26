# lib/familia/features/relationships/collection_operations.rb

module Familia
  module Features
    module Relationships
      # Shared collection operations for Participation module
      # Provides common methods for creating and manipulating Valkey/Redis collections
      # Used by both ParticipantMethods and TargetMethods to reduce duplication
      module CollectionOperations
        using Familia::Refinements::StylizeWords

        # Create a collection instance with proper key and database settings
        # @param context [Class, Object] The context (class or instance) for the collection
        # @param collection_name [Symbol] Name of the collection
        # @param type [Symbol] Collection type (:sorted_set, :set, :list)
        # @param identifier [String, nil] Optional identifier for instance collections
        # @return [Familia::DataType] The collection instance
        def create_collection(context, collection_name, type, identifier = nil)
          collection_class = Familia::DataType.registered_type(type)
          key = build_collection_key(context, collection_name, identifier)
          logical_db = determine_logical_database(context)

          collection_class.new(nil, dbkey: key, logical_database: logical_db)
        end

        # Add an item to a collection, handling type-specific operations
        # @param collection [Familia::DataType] The collection to add to
        # @param item [Object] The item to add (must respond to identifier)
        # @param score [Float, nil] Score for sorted sets
        # @param type [Symbol] Collection type
        def add_to_collection(collection, item, score: nil, type:)
          case type
          when :sorted_set
            # Ensure score is never nil for sorted sets
            score ||= calculate_item_score(item)
            collection.add(score, item.identifier)
          when :list
            # Lists use push/unshift operations
            collection.add(item.identifier)
          when :set
            # Sets use simple add
            collection.add(item.identifier)
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
          collection.remove(item.identifier)
        end

        # Check if an item is a member of a collection
        # @param collection [Familia::DataType] The collection to check
        # @param item [Object] The item to check (must respond to identifier)
        # @return [Boolean] True if item is in collection
        def member_of_collection?(collection, item)
          collection.member?(item.identifier)
        end

        # Bulk add items to a collection
        # @param collection [Familia::DataType] The collection to add to
        # @param items [Array] Array of items to add
        # @param type [Symbol] Collection type
        def bulk_add_to_collection(collection, items, type:)
          return if items.empty?

          case type
          when :sorted_set
            # Prepare scores and identifiers for bulk zadd
            members = items.map do |item|
              score = calculate_item_score(item)
              [score, item.identifier]
            end
            collection.zadd(members)
          when :set
            # Bulk add to set
            identifiers = items.map(&:identifier)
            collection.sadd(identifiers)
          when :list
            # Bulk push to list
            identifiers = items.map(&:identifier)
            collection.rpush(identifiers)
          else
            raise ArgumentError, "Unknown collection type: #{type}"
          end
        end

        private

        # Build a collection key based on context
        # @param context [Class, Object, String, Symbol] The context for the key
        # @param collection_name [Symbol] Name of the collection
        # @param identifier [String, nil] Optional identifier
        # @return [String] The constructed Redis key
        def build_collection_key(context, collection_name, identifier = nil)
          keyparts = case context
          when Class
            if identifier
              # Instance-level collection with class context: "customer:cust123:domains"
              [context.config_name, identifier, collection_name]
            else
              # Class-level collection: "user:all_users"
              [context.config_name, collection_name]
            end
          when String, Symbol
            # String/Symbol context for class collections: "user:active"
            [context.to_s.snake_case, collection_name]
          else
            # Instance-level collection: "customer:cust123:domains"
            id = identifier || context.identifier
            [context.class.config_name, id, collection_name]
          end
          Familia.join(*keyparts)
        end

        # Determine the logical database for a context
        # @param context [Class, Object] The context
        # @return [Integer, nil] The logical database number
        def determine_logical_database(context)
          if context.respond_to?(:logical_database)
            context.logical_database
          elsif context.class.respond_to?(:logical_database)
            context.class.logical_database
          else
            nil
          end
        end

        # Calculate score for an item
        # @param item [Object] The item to score
        # @return [Float] The calculated score
        def calculate_item_score(item)
          if item.respond_to?(:calculate_participation_score)
            item.calculate_participation_score
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
