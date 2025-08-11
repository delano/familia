# lib/familia/field_types/encrypted_field_type.rb

require_relative '../../field_type'
require_relative 'concealed_string'

module Familia
  class EncryptedFieldType < FieldType
    attr_reader :aad_fields

    def initialize(name, aad_fields: [], **options)
      # Encrypted fields are not loggable by default for security
      super(name, **options.merge(on_conflict: :raise, loggable: false))
      @aad_fields = Array(aad_fields).freeze
    end

    def define_setter(klass)
      field_name = @name
      method_name = @method_name
      field_type = self

      handle_method_conflict(klass, :"#{method_name}=") do
        klass.define_method :"#{method_name}=" do |value|
          if value.nil?
            instance_variable_set(:"@#{field_name}", nil)
          elsif value.is_a?(ConcealedString)
            # Already concealed, store as-is
            instance_variable_set(:"@#{field_name}", value)
          else
            # Encrypt plaintext and wrap in ConcealedString
            encrypted = field_type.encrypt_value(self, value)
            concealed = ConcealedString.new(encrypted, self, field_type)
            instance_variable_set(:"@#{field_name}", concealed)
          end
        end
      end
    end

    def define_getter(klass)
      field_name = @name
      method_name = @method_name
      field_type = self

      handle_method_conflict(klass, method_name) do
        klass.define_method method_name do
          # Return ConcealedString directly - no auto-decryption!
          # Caller must use .reveal { } for plaintext access
          instance_variable_get(:"@#{field_name}")
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

          # Set via the setter method to get proper ConcealedString wrapping
          send(:"#{method_name}=", val) if method_name

          # Get the ConcealedString and extract encrypted data for storage
          concealed = instance_variable_get(:"@#{field_name}")
          encrypted_data = concealed&.encrypted_value

          return false if encrypted_data.nil?

          ret = hset(field_name, encrypted_data)
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

    # Build Additional Authenticated Data (AAD) for authenticated encryption
    #
    # AAD provides cryptographic binding between encrypted field values and their
    # containing record context. This prevents attackers from moving encrypted
    # values between different records or field contexts, even with database access.
    #
    # ## Persistence-Dependent Behavior
    #
    # AAD is only generated for records that exist in the database (`record.exists?`).
    # This creates an important behavioral distinction:
    #
    # **Before Save (record.exists? == false):**
    # - AAD = nil
    # - Encryption context = "ClassName:fieldname:identifier" only
    # - Values can be encrypted/decrypted freely in memory
    #
    # **After Save (record.exists? == true):**
    # - AAD = record.identifier (no aad_fields) or SHA256(identifier:field1:field2:...)
    # - Full cryptographic binding to database state
    # - Moving encrypted values between records/contexts will fail decryption
    #
    # ## Security Implications
    #
    # This design prevents several attack vectors:
    #
    # 1. **Field Value Swapping**: With aad_fields specified, encrypted values
    #    become bound to other field values. Changing owner_id breaks decryption.
    #
    # 2. **Cross-Record Migration**: Even without aad_fields, encrypted values
    #    are bound to their specific record identifier after persistence.
    #
    # 3. **Temporal Consistency**: Re-encrypting the same plaintext after
    #    field changes produces different ciphertext due to AAD changes.
    #
    # ## Usage Patterns
    #
    # ```ruby
    # # No AAD fields - basic record binding
    # encrypted_field :secret_value
    #
    # # With AAD fields - multi-field binding
    # encrypted_field :content, aad_fields: [:owner_id, :doc_type]
    # ```
    #
    # @param record [Familia::Horreum] The record instance containing this field
    # @return [String, nil] AAD string for encryption, or nil for unsaved records
    #
    def build_aad(record)
      return nil unless record.exists?

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
