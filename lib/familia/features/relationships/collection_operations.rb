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
        #
        # When +participant_class+ is provided, the collection is declared with
        # +record_class:+ pointing at the participant class. This is a
        # loading-only hint: it lets +each_record+ hydrate the stored participant
        # identifiers via +load_multi+ (issue #297) WITHOUT changing how the
        # collection deserializes reads. +members+/+member?+/+score+ keep the
        # generic DataType semantics, so adding participation to a collection is
        # transparent to existing readers.
        #
        # This deliberately differs from +instances+ and +unique_index+, which
        # use +class: + reference: true+ because they also want raw-string read
        # semantics. Participation only needs the loading capability, so it uses
        # the narrower +record_class:+ option and avoids any read-behavior change.
        #
        # @param target_class [Class] The class that should have the collection
        # @param collection_name [Symbol] Name of the collection field
        # @param type [Symbol] Collection type (:sorted_set, :set, :list)
        # @param participant_class [Class, nil] The class whose identifiers the
        #   collection stores (the participant). When nil, the collection is
        #   declared with no record_class (each_record stays unavailable).
        # @param max_length [Integer, nil] Cap for the collection (issue #351),
        #   validated eagerly so a bad value or unsupported type fails at class
        #   definition time rather than on first access. When the collection is
        #   pre-declared, the caps must agree — see assert_compatible_cap!.
        def ensure_collection_field(target_class, collection_name, type, participant_class: nil, max_length: nil)
          validate_max_length_option!(type, max_length)

          if target_class.method_defined?(collection_name)
            existing = target_class.related_fields[collection_name.to_s.to_sym]
            assert_compatible_cap!(existing, max_length, target_class, collection_name, type)
            return
          end

          opts = {}
          opts[:record_class] = participant_class if participant_class
          opts[:max_length] = max_length if max_length
          target_class.send(type, collection_name, **opts)
        end

        # Eager definition-time validation for a max_length: passed through
        # participation. The DataType itself validates in #initialize, but for
        # instance-level relations that instance is created lazily on first
        # accessor call — too late to point at the participates_in line that
        # caused it. No-op when max_length is nil.
        #
        # @raise [ArgumentError] on a non-positive/non-Integer value or a
        #   collection type that does not implement capping
        def validate_max_length_option!(type, max_length)
          return if max_length.nil?

          unless max_length.is_a?(Integer) && max_length.positive?
            raise ArgumentError, "max_length must be a positive Integer, got #{max_length.inspect}"
          end

          return if Familia::DataType.registered_type(type)&.supports_max_length?

          raise ArgumentError,
                "max_length: is not supported for type: #{type.inspect} collections " \
                '(only :sorted_set and :list implement capping)'
        end

        # When a participation declaration requests a cap but the collection
        # accessor already exists, the existing declaration wins (participation
        # never overwrites it). Agreement is fine — repeating the cap is
        # harmless — but a mismatch would silently produce a collection with
        # the wrong cap (or none), so it raises instead. No-op when the
        # participation declaration did not request a cap: a pre-declared cap
        # is kept as-is, preserving the pre-declaration pattern.
        #
        # @param existing [RelatedFieldDefinition, nil] the pre-existing
        #   declaration, if the accessor came from a related-field DSL call
        # @raise [ArgumentError] when the requested cap differs from the
        #   declared one
        def assert_compatible_cap!(existing, max_length, target_class, collection_name, type)
          return if max_length.nil?

          declared_max = existing&.opts&.fetch(:max_length, nil)
          return if declared_max == max_length

          raise ArgumentError, <<~ERROR
            max_length: #{max_length} conflicts with the existing :#{collection_name} declaration
            on #{target_class} (max_length: #{declared_max.inspect}).

            Participation does not overwrite a collection that is already declared. Either
            remove max_length: from the participation declaration, or give the
            `#{type} :#{collection_name}` declaration on #{target_class} the same cap.
          ERROR
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
