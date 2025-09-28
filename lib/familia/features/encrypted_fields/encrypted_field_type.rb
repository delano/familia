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
          elsif value.is_a?(::String) && value.empty?
            # Handle empty strings - treat as nil for encrypted fields
            instance_variable_set(:"@#{field_name}", nil)
          elsif value.is_a?(ConcealedString)
            # Already concealed, store as-is
            instance_variable_set(:"@#{field_name}", value)
          elsif field_type.encrypted_json?(value)
            # Already encrypted JSON from database - wrap in ConcealedString without re-encrypting
            concealed = ConcealedString.new(value, self, field_type)
            instance_variable_set(:"@#{field_name}", concealed)
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
          concealed = instance_variable_get(:"@#{field_name}")

          # Return nil directly if that's what was set
          return nil if concealed.nil?

          # If we have a raw string (from direct instance variable manipulation),
          # wrap it in ConcealedString which will trigger validation
          if concealed.is_a?(::String) && !concealed.is_a?(ConcealedString)
            # This happens when someone directly sets the instance variable
            # (e.g., during tampering tests). Wrapping in ConcealedString
            # will trigger validate_decryptable! and catch invalid algorithms
            begin
              concealed = ConcealedString.new(concealed, self, field_type)
              instance_variable_set(:"@#{field_name}", concealed)
            rescue Familia::EncryptionError => e
              # Increment derivation counter for failed validation attempts (similar to decrypt failures)
              Familia::Encryption.derivation_count.increment
              raise e
            end
          end

          # Context validation: detect cross-context attacks
          # Only validate if we have a proper ConcealedString instance
          if concealed.is_a?(ConcealedString) && !concealed.belongs_to_context?(self, field_name)
            raise Familia::EncryptionError,
                  "Context isolation violation: encrypted field '#{field_name}' does not belong to #{self.class.name}:#{identifier}"
          end

          concealed
        end
      end
    end

    def define_fast_writer(klass)
      # Encrypted fields override base fast writer for security
      return unless @fast_method_name&.to_s&.end_with?('!')

      field_name = @name
      method_name = @method_name
      fast_method_name = @fast_method_name
      self

      handle_method_conflict(klass, fast_method_name) do
        klass.define_method fast_method_name do |val|
          raise ArgumentError, "#{fast_method_name} requires a value" if val.nil?

          # UnsortedSet via the setter method to get proper ConcealedString wrapping
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

    # Check if a string looks like encrypted JSON data
    def encrypted_json?(data)
      Familia::Encryption::EncryptedData.valid?(data)
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
    # ## Consistent AAD Behavior
    #
    # AAD is now consistently generated based on the record's identifier, regardless
    # of persistence state. This ensures that encrypted values remain decryptable
    # after save/load cycles while still providing security benefits.
    #
    # **All Records (both new and persisted):**
    # - AAD = record.identifier (no aad_fields) or SHA256(identifier:field1:field2:...)
    # - Consistent cryptographic binding to record identity
    # - Moving encrypted values between records/contexts will fail decryption
    #
    # ## Security Implications
    #
    # This design prevents several attack vectors:
    #
    # 1. **Field Value Swapping**: With aad_fields specified, encrypted values
    #    become bound to other field values. Changing owner_id breaks decryption.
    #
    # 2. **Cross-Record Migration**: Encrypted values are bound to their specific
    #    record identifier, preventing cross-record value movement.
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
    # @return [String, nil] AAD string for encryption, or nil if no identifier
    #
    def build_aad(record)
      # AAD provides consistent context-aware binding, regardless of persistence state
      # This ensures save/load cycles work while maintaining context isolation
      identifier = record.identifier
      return nil if identifier.nil? || identifier.to_s.empty?

      # Include class and field name in AAD for context isolation
      # This prevents cross-class and cross-field value migration
      base_components = [record.class.name, @name, identifier]

      if @aad_fields.empty?
        # When no AAD fields specified, use class:field:identifier
        base_components.join(':')
      elsif record.exists?
        # For unsaved records, don't enforce AAD fields since they can change
        # For saved records, include field values for tamper protection
        values = @aad_fields.map { |field| record.send(field) }
        all_components = [*base_components, *values].compact
        Digest::SHA256.hexdigest(all_components.join(':'))
      # Include specified field values in AAD for persisted records
      else
        # For unsaved records, only use class:field:identifier for context isolation
        base_components.join(':')
      end
    end
  end
end
