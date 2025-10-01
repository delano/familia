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
      ParticipationRelationship = Data.define(
        :target_class,        # Class object that owns the collection
        :collection_name,     # Symbol name of the collection (e.g., :members, :domains)
        :score,               # Proc/Symbol/nil - score calculator for sorted sets
        :type,                # Symbol - collection type (:sorted_set, :set, :list)
        :bidirectional, # Boolean - whether to generate reverse methods
      ) do
        #
        # Get the normalized config name for the target class
        #
        # @return [String] The config name (e.g., "user", "perf_test_customer")
        #
        def target_class_config_name
          target_class.config_name
        end
      end
    end
  end
end
