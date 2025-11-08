# lib/familia/features/relationships/participation_relationship.rb

module Familia
  module Features
    module Relationships
      #
      # ParticipationRelationship
      #
      # Stores metadata about participation relationships defined at class level.
      # Used to configure code generation and runtime behavior for participates_in
      # and class_participates_in declarations.
      #
      # @note target_class is resolved once at definition time for performance.
      #   Use _original_target for debugging/introspection to see what was passed.
      #
      ParticipationRelationship = Data.define(
        :_original_target,    # Original Symbol/String/Class as passed to participates_in
        :target_class,        # Resolved Class object (e.g., User class, not :User symbol)
        :collection_name,     # Symbol name of the collection (e.g., :members, :domains)
        :score,               # Proc/Symbol/nil - score calculator for sorted sets
        :type,                # Symbol - collection type (:sorted_set, :set, :list)
        :bidirectional,       # Boolean/Symbol - whether to generate reverse methods
      ) do
        # Get a unique key for this participation relationship
        # Useful for comparisons and hash keys
        #
        # @return [String] unique identifier in format "TargetClass:collection_name"
        def unique_key
          Familia::Utils.join([target_class_base, collection_name])
        end

        # Get the base class name without namespace
        # Handles anonymous class wrappers like "#<Class:0x123>::SymbolResolutionCustomer"
        #
        # @return [String] base class name (e.g., "Customer")
        def target_class_base
          target_class.name.split('::').last
        end

        # Check if this relationship matches the given target and collection
        # Handles namespace-agnostic class comparison
        #
        # @param comparison_target [Class, String, Symbol] target to compare against
        # @param comparison_collection [Symbol, String] collection name to compare
        # @return [Boolean] true if both target and collection match
        def matches?(comparison_target, comparison_collection)
          # Normalize comparison target to base class name
          comparison_target = comparison_target.name if comparison_target.is_a?(Class)
          comparison_target_base = comparison_target.to_s.split('::').last

          target_class_base == comparison_target_base &&
            collection_name == comparison_collection.to_sym
        end
      end
    end
  end
end
