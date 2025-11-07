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
      )
    end
  end
end
