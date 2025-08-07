# lib/familia/field_types/encrypted_field_type.rb

require 'familia/field_type'

module Familia
  class EncryptedFieldType < FieldType
    attr_reader :aad_fields

    def initialize(name, aad_fields: [], **options)
      super(name, **options.merge(on_conflict: :raise))
      @aad_fields = Array(aad_fields).freeze
    end

    def define_setter(klass)
      field_name = @name
      method_name = @method_name
      field_type = self

      handle_method_conflict(klass, :"#{method_name}=") do
        klass.define_method :"#{method_name}=" do |value|
          encrypted = value.nil? ? nil : field_type.encrypt_value(self, value)
          instance_variable_set(:"@#{field_name}", encrypted)
        end
      end
    end

    def define_getter(klass)
      field_name = @name
      method_name = @method_name
      field_type = self

      handle_method_conflict(klass, method_name) do
        klass.define_method method_name do
          encrypted = instance_variable_get(:"@#{field_name}")
          encrypted.nil? ? nil : field_type.decrypt_value(self, encrypted)
        end
      end
    end

    def define_fast_writer(klass)
      # Encrypted fields override base fast writer for security
      return unless @fast_method_name&.to_s&.end_with?('!')

      field_name = @name
      method_name = @method_name
      fast_method_name = @fast_method_name
      field_type = self

      handle_method_conflict(klass, fast_method_name) do
        klass.define_method fast_method_name do |val|
          raise ArgumentError, "#{fast_method_name} requires a value" if val.nil?

          encrypted = field_type.encrypt_value(self, val)
          send(:"#{method_name}=", val) if method_name

          ret = hset(field_name, encrypted)
          ret.zero? || ret.positive?
        end
      end
    end

    # Encrypt a value for the given record
    def encrypt_value(record, value)
      context = build_context(record)
      additional_data = build_aad(record)

      Familia::Encryption.encrypt(value, context: context, additional_data: additional_data)
    end

    # Decrypt a value for the given record
    def decrypt_value(record, encrypted)
      context = build_context(record)
      additional_data = build_aad(record)

      Familia::Encryption.decrypt(encrypted, context: context, additional_data: additional_data)
    end

    def persistent?
      true
    end

    def category
      :encrypted
    end

    private

    # Build encryption context string
    def build_context(record)
      "#{record.class.name}:#{@name}:#{record.identifier}"
    end

    # Build Additional Authenticated Data
    def build_aad(record)
      return nil unless record.persisted?

      if @aad_fields.empty?
        # When no AAD fields specified, just use identifier
        record.identifier
      else
        # Include specified field values in AAD
        values = @aad_fields.map { |field| record.send(field) }
        Digest::SHA256.hexdigest([record.identifier, *values].compact.join(':'))
      end
    end
  end
end
