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
      # Terminology:
      # - `scope_class`: The class that provides the uniqueness boundary for
      #   instance-scoped indexes. For example, in `unique_index :badge_number,
      #   :badge_index, within: Company`, the Company is the scope class.
      # - `within`: Preserves the original DSL parameter to explicitly distinguish
      #   class-level indexes (within: nil) from instance-scoped indexes (within:
      #   SomeClass). This avoids brittle class comparisons and prevents issues
      #   with inheritance scenarios.
      #
      IndexingRelationship = Data.define(
        :field,              # Symbol - field being indexed (e.g., :email, :department)
        :index_name,         # Symbol - name of the index (e.g., :email_index, :dept_index)
        :scope_class,        # Class/Symbol - scope class for instance-scoped indexes (within:)
        :within,             # Class/Symbol/nil - within: parameter (nil for class-level, Class for instance-scoped)
        :cardinality,        # Symbol - :unique (1:1) or :multi (1:many)
        :query               # Boolean - whether to generate query  methods
      ) do
        #
        # Get the normalized config name for the scope class
        #
        # @return [String] The config name (e.g., "user", "company", "test_company")
        #
        def scope_class_config_name
          scope_class.config_name
        end
      end
    end
  end
end
