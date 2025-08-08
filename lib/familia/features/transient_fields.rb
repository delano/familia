# lib/familia/features/transient_fields.rb

require_relative 'transient_fields/redacted_string'

module Familia
  module Features
    # Familia::Features::TransientFields
    #
    # Provides secure transient fields that wrap sensitive values in RedactedString
    # objects. These fields are excluded from serialization operations and provide
    # automatic memory wiping for security.
    #
    module TransientFields
      def self.included(base)
        Familia.ld "[#{base}] Loaded #{self}"
        base.extend ClassMethods
      end

      # ClassMethods
      #
      module ClassMethods
        # Define a transient field that automatically wraps values in RedactedString
        #
        # @param name [Symbol] The field name
        # @param as [Symbol] The method name (defaults to field name)
        # @param kwargs [Hash] Additional field options
        #
        # @example Define a transient API key field
        #   class Service < Familia::Horreum
        #     feature :transient_fields
        #     transient_field :api_key
        #   end
        #
        def transient_field(name, as: name, **kwargs)
          # Use the field type system - much cleaner than alias_method approach!
          # We can now remove the transient_field method from this feature entirely
          # since it's built into DefinitionMethods using TransientFieldType
          require_relative 'transient_fields/transient_field_type'
          field_type = TransientFieldType.new(name, as: as, **kwargs.merge(fast_method: false))
          register_field_type(field_type)
        end
      end

      Familia::Base.add_feature self, :transient_fields, depends_on: nil
    end
  end
end
