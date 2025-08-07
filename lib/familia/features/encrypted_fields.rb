# lib/familia/features/encrypted_fields.rb

require_relative 'encrypted_fields/encrypted_field_type'

module Familia
  module Features
    module EncryptedFields
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # Define an encrypted field
        # @param name [Symbol] Field name
        # @param aad_fields [Array<Symbol>] Optional fields to include in AAD
        # @param kwargs [Hash] Additional field options
        def encrypted_field(name, aad_fields: [], **kwargs)
          require_relative '../field_types/encrypted_field_type'

          field_type = EncryptedFieldType.new(name, aad_fields: aad_fields, **kwargs)
          register_field_type(field_type)
        end
      end

      Familia::Base.add_feature self, :encrypted_fields
    end
  end
end
