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
      # @example
      #   relationship = ParticipationRelationship.new(
      #     target_class: User,
      #     collection_name: :members,
      #     score: :created_at,
      #     on_destroy: :remove,
      #     type: :sorted_set,
      #     bidirectional: true
      #   )
      #
      ParticipationRelationship = Data.define(
        :target_class,        # Class object that owns the collection
        :target_class_name,
        :collection_name,     # Symbol name of the collection (e.g., :members, :domains)
        :score,               # Proc/Symbol/nil - score calculator for sorted sets
        :on_destroy,          # Symbol - cleanup behavior (:remove, :cascade, etc.)
        :type,                # Symbol - collection type (:sorted_set, :set, :list)
        :bidirectional        # Boolean - whether to generate reverse methods
      ) do
        #
        # Get the target class name as a string
        #
        # @return [String] The class name (e.g., "User", "PerfTestCustomer")
        #
        # def target_class_name
        #   # Extract just the class name, removing anonymous class prefixes like "#<Class:0x123>::"
        #   name = target_class.name
        #   name&.split('::')&.last || name
        # end

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
