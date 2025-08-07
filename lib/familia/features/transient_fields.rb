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
          # Force specific options for transient fields
          field name, as: as, fast_method: false, on_conflict: :raise, category: :transient, **kwargs

          # Get the method name that was just created
          method_name = as
          original_setter = "#{method_name}="

          # Save reference to the original setter before overriding
          alias_method "#{original_setter}_original", original_setter

          # Override the setter to wrap values in RedactedString
          define_method original_setter do |value|
            # Handle nil values by storing nil directly
            if value.nil?
              send("#{original_setter}_original", nil)
            else
              # Handle cases where value is already a RedactedString
              wrapped_value = value.is_a?(RedactedString) ? value : RedactedString.new(value)
              send("#{original_setter}_original", wrapped_value)
            end
          end
        end
      end

      Familia::Base.add_feature self, :transient_fields, depends_on: nil
    end
  end
end
