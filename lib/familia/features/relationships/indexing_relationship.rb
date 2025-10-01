# frozen_string_literal: true

module Familia
  module Features
    module Relationships
      using Familia::Refinements::StylizeWords

      # IndexingRelationship
      #
      # Stores metadata about indexing relationships defined at class level.
      # Used to configure code generation and runtime behavior for unique_index
      # and multi_index declarations.
      #
      # Similar to ParticipationRelationship but for attribute-based lookups
      # rather than collection membership.
      #
      IndexingRelationship = Data.define(
        :field,              # Symbol - field being indexed (e.g., :email, :department)
        :index_name,         # Symbol - name of the index (e.g., :email_index, :dept_index)
        :target_class,       # Class/Symbol - parent class for instance-scoped indexes (within:)
        :target_class_name,  # String - demodularized class name for method generation
        :cardinality,        # Symbol - :unique (1:1) or :multi (1:many)
        :query               # Boolean - whether to generate query  methods
      ) do
        #
        # Get the normalized config name for the target class
        #
        # @return [String] The config name (e.g., "user", "company", "test_company")
        #
        def target_class_config_name
          target_class.config_name
        end
      end
    end
  end
end
