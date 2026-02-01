# lib/familia/features/schema_validation.rb
#
# frozen_string_literal: true

module Familia
  module Features
    # Adds JSON schema validation methods to Horreum models.
    # Schemas are loaded from external files via SchemaRegistry.
    #
    # This feature provides instance-level validation against JSON schemas,
    # enabling data integrity checks before persistence or during API operations.
    #
    # Example:
    #
    #   class Customer < Familia::Horreum
    #     feature :schema_validation
    #     identifier_field :custid
    #     field :custid
    #     field :email
    #   end
    #
    #   # With schema at schemas/customer.json
    #   customer = Customer.new(custid: 'c1', email: 'invalid')
    #   customer.valid_against_schema?      # => false
    #   customer.schema_validation_errors   # => [...]
    #   customer.validate_against_schema!   # raises SchemaValidationError
    #
    # Schema Loading:
    #
    # Schemas are loaded by SchemaRegistry based on class names. Configure
    # schema loading before enabling this feature:
    #
    #   # Convention-based loading
    #   Familia.schema_path = 'schemas/models'
    #   # Loads schemas/models/customer.json for Customer class
    #
    #   # Explicit mapping
    #   Familia.schemas = { 'Customer' => 'schemas/customer.json' }
    #
    # Validation Behavior:
    #
    # - Returns true/valid if no schema is defined for the class
    # - Uses json_schemer gem for validation when available
    # - Falls back to null validation (always passes) if gem not installed
    #
    # Integration Patterns:
    #
    #   # Validate before save
    #   class Order < Familia::Horreum
    #     feature :schema_validation
    #
    #     def save
    #       validate_against_schema!
    #       super
    #     end
    #   end
    #
    #   # Conditional validation
    #   class User < Familia::Horreum
    #     feature :schema_validation
    #
    #     def save
    #       if self.class.schema_defined?
    #         return false unless valid_against_schema?
    #       end
    #       super
    #     end
    #   end
    #
    # Error Handling:
    #
    # The validate_against_schema! method raises SchemaValidationError with
    # detailed error information:
    #
    #   begin
    #     customer.validate_against_schema!
    #   rescue Familia::SchemaValidationError => e
    #     e.errors  # => [{ 'data_pointer' => '/email', 'type' => 'format', ... }]
    #   end
    #
    # @see Familia::SchemaRegistry for schema loading and configuration
    # @see Familia::SchemaValidationError for error details
    #
    module SchemaValidation
      Familia::Base.add_feature self, :schema_validation

      def self.included(base)
        Familia.trace :LOADED, self, base if Familia.debug?
        base.extend(ClassMethods)
      end

      # Class-level schema access methods
      module ClassMethods
        # Get the JSON schema for this class
        # @return [Hash, nil] the parsed schema or nil if not defined
        def schema
          Familia::SchemaRegistry.schema_for(name)
        end

        # Check if a schema is defined for this class
        # @return [Boolean]
        def schema_defined?
          Familia::SchemaRegistry.schema_defined?(name)
        end
      end

      # Get the schema for this instance's class
      # @return [Hash, nil]
      def schema
        self.class.schema
      end

      # Check if the current state validates against the schema
      # @return [Boolean] true if valid or no schema defined
      def valid_against_schema?
        return true unless self.class.schema_defined?

        Familia::SchemaRegistry.validate(self.class.name, to_h)[:valid]
      end

      # Get validation errors for the current state
      # @return [Array<Hash>] array of error objects (empty if valid)
      def schema_validation_errors
        return [] unless self.class.schema_defined?

        Familia::SchemaRegistry.validate(self.class.name, to_h)[:errors]
      end

      # Validate current state or raise SchemaValidationError
      # @return [true] if valid
      # @raise [SchemaValidationError] if validation fails
      def validate_against_schema!
        return true unless self.class.schema_defined?

        Familia::SchemaRegistry.validate!(self.class.name, to_h)
      end
    end
  end
end
