# lib/familia/features/relationships/participation_membership.rb
#
# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      #
      # ParticipationMembership
      #
      # Represents runtime snapshot of a participant's membership in a target collection.
      # Returned by current_participations to provide a type-safe, structured view
      # of actual participation state.
      #
      # @note This represents what currently exists in Redis, not just configuration.
      #   See ParticipationRelationship for static configuration metadata.
      #
      # @example
      #   membership = user.current_participations.first
      #   membership.target_class  # => "Team"
      #   membership.target_id     # => "team123"
      #   membership.collection_name  # => :members
      #   membership.type          # => :sorted_set
      #   membership.score         # => 1762554020.05
      #
      ParticipationMembership = Data.define(
        :target_class,      # String - class name (e.g., "Customer")
        :target_id,         # String - target instance identifier
        :collection_name,   # Symbol - collection name (e.g., :domains)
        :type,              # Symbol - collection type (:sorted_set, :set, :list)
        :score,             # Float - optional, for sorted_set only
        :decoded_score,     # Hash - optional, decoded score data
        :position           # Integer - optional, for list only
      ) do
        # Check if this membership is a sorted set
        # @return [Boolean]
        def sorted_set?
          type == :sorted_set
        end

        # Check if this membership is a set
        # @return [Boolean]
        def set?
          type == :set
        end

        # Check if this membership is a list
        # @return [Boolean]
        def list?
          type == :list
        end

        # Get the target instance (requires loading from database)
        # @return [Familia::Horreum, nil] the loaded target instance
        def target_instance
          return nil unless target_class

          # SECURITY: target_class is a string persisted in the database. Using
          # Object.const_get on it would let anyone able to write to the database
          # choose which constant gets resolved (and whose code runs next). Look
          # the name up through Familia's model registry instead -- it only ever
          # returns a class that was explicitly registered as a Familia model,
          # acting as an implicit allowlist. Unknown names resolve to nil rather
          # than to an arbitrary constant. See issue #310 (S4).
          klass = Familia.resolve_class(target_class)
          return nil unless klass.respond_to?(:find_by_id)

          klass.find_by_id(target_id)
        rescue ArgumentError, NameError
          # Unresolvable or non-model class name -- treat as a missing target.
          nil
        end
      end
    end
  end
end
