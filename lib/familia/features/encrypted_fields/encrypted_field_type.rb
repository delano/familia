# lib/familia/features/encrypted_fields/encrypted_field_type.rb
#
# frozen_string_literal: true

# lib/familia/field_types/encrypted_field_type.rb

require_relative '../../field_type'
require_relative 'concealed_string'

module Familia
  class EncryptedFieldType < FieldType
    attr_reader :aad_fields, :key_material

    def initialize(name, aad_fields: [], key_material: nil, **options)
      # Encrypted fields are not loggable by default for security
      super(name, **options.merge(on_conflict: :raise, loggable: false))
      @aad_fields = Array(aad_fields).freeze
      @key_material = key_material # Proc returning entropy string
    end

    def define_setter(klass)
      field_name = @name
      method_name = @method_name
      field_type = self

      handle_method_conflict(klass, :"#{method_name}=") do
        klass.define_method :"#{method_name}=" do |value|
          old_value = instance_variable_get(:"@#{field_name}")

          if value.nil?
            instance_variable_set(:"@#{field_name}", nil)
          elsif value.is_a?(::String) && value.empty?
            # Handle empty strings - treat as nil for encrypted fields
            instance_variable_set(:"@#{field_name}", nil)
          elsif value.is_a?(ConcealedString)
            # Already concealed, store as-is
            instance_variable_set(:"@#{field_name}", value)
          elsif field_type.encrypted_json?(value)
            # Already encrypted (JSON string or Hash from database) - wrap in ConcealedString without re-encrypting
            # Convert Hash back to JSON string if needed (v2.0 deserialization returns Hash)
            encrypted_string = value.is_a?(Hash) ? Familia::JsonSerializer.dump(value) : value
            concealed = ConcealedString.new(encrypted_string, self, field_type)
            instance_variable_set(:"@#{field_name}", concealed)
          else
            # Encrypt plaintext and wrap in ConcealedString
            encrypted = field_type.encrypt_value(self, value)
            concealed = ConcealedString.new(encrypted, self, field_type)
            instance_variable_set(:"@#{field_name}", concealed)
          end

          # Track the change for dirty-tracking (only for Horreum instances)
          mark_dirty!(field_name, old_value) if respond_to?(:mark_dirty!)
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

          # Use via the setter method to get proper ConcealedString wrapping
          send(:"#{method_name}=", val) if method_name

          # Get the ConcealedString and extract encrypted data for storage
          concealed = instance_variable_get(:"@#{field_name}")
          encrypted_data = concealed&.encrypted_value

          return false if encrypted_data.nil?

          ret = hset(field_name, encrypted_data)
          Familia.success?(ret)
        end
      end
    end

    # Encrypt a value for the given record
    def encrypt_value(record, value)
      context = build_context(record)
      additional_data = build_aad(record)

      # Extend context with key_material if present
      entropy = build_key_material(record)
      context = "#{context}:#{entropy}" if entropy

      result = Familia::Encryption.encrypt(value, context: context, additional_data: additional_data)

      # Add envelope metadata for decryption
      envelope = Familia::JsonSerializer.parse(result)
      envelope['envelope_version'] = 2
      envelope['aad_fields'] = @aad_fields.map(&:to_s) unless @aad_fields.empty?
      envelope['key_material_fields'] = ['key_material'] if entropy

      Familia::JsonSerializer.dump(envelope)
    end

    # Decrypt a value for the given record
    def decrypt_value(record, encrypted)
      # Parse envelope to check for key_material_fields
      envelope = if encrypted.is_a?(Hash)
                   encrypted
                 else
                   Familia::JsonSerializer.parse(encrypted)
                 end

      context = build_context(record)

      # Reconstruct AAD from envelope's aad_fields if present, else use class-level @aad_fields
      aad_field_names = envelope['aad_fields'] || envelope[:aad_fields]
      additional_data = if aad_field_names
                          build_aad_from_fields(record, aad_field_names.map(&:to_sym))
                        else
                          build_aad(record)
                        end

      # Check if key_material was used during encryption
      key_material_fields = envelope['key_material_fields'] || envelope[:key_material_fields]
      if key_material_fields
        entropy = build_key_material(record)
        context = "#{context}:#{entropy}" if entropy
      end

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
      # Support both JSON strings (legacy) and Hashes (v2.0 deserialization)
      if data.is_a?(Hash)
        required_keys = %w[algorithm nonce ciphertext auth_tag key_version]
        required_keys.all? { |key| data.key?(key) || data.key?(key.to_sym) }
      else
        Familia::Encryption::EncryptedData.valid?(data)
      end
    end

    private

    # Build encryption context string
    def build_context(record)
      "#{record.class.name}:#{@name}:#{record.identifier}"
    end

    # Build key material from proc for mixing into key derivation
    #
    # Key material is mixed into BLAKE2b derivation, meaning wrong value
    # produces a completely wrong key and garbage output (unlike AAD which
    # causes auth_tag mismatch).
    #
    # @param record [Familia::Horreum] The record instance
    # @return [String, nil] Entropy string for key derivation, or nil
    def build_key_material(record)
      return nil unless @key_material

      result = @key_material.call(record)
      return nil if result.nil?

      if result.is_a?(::RedactedString)
        result.value
      else
        result.to_s
      end
    end

    # Build AAD from explicit field list (used during decryption with envelope)
    #
    # @param record [Familia::Horreum] The record instance
    # @param field_names [Array<Symbol>] Field names to include in AAD
    # @return [String, nil] AAD string
    def build_aad_from_fields(record, field_names)
      identifier = record.identifier
      return nil if identifier.nil? || identifier.to_s.empty?

      base_components = [record.class.name, @name, identifier]

      if field_names.empty?
        base_components.join(':')
      else
        values = field_names.map do |field|
          raw = record.send(field)
          if raw.is_a?(::RedactedString)
            raw.value
          else
            raw.to_s
          end
        end
        all_components = [*base_components, *values]
        Digest::SHA256.hexdigest(all_components.join(':'))
      end
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
      else
        # Always include aad_field values regardless of persistence state.
        # The field values are available on the record before save and must
        # produce identical AAD at both encrypt and decrypt time.
        #
        # .to_s coerces nil to "" so that every declared AAD field occupies
        # a fixed position in the join. Without this, a nil field would
        # shift later values left and produce a different hash once the
        # field is populated — making existing ciphertext undecryptable.
        values = @aad_fields.map do |field|
          raw = record.send(field)
          if raw.is_a?(::RedactedString)
            raw.value
          else
            raw.to_s
          end
        end
        all_components = [*base_components, *values]
        Digest::SHA256.hexdigest(all_components.join(':'))
      end
    end
  end
end
