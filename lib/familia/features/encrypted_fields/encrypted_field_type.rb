# lib/familia/features/encrypted_fields/encrypted_field_type.rb
#
# frozen_string_literal: true

# lib/familia/field_types/encrypted_field_type.rb

require_relative '../../field_type'
require_relative 'concealed_string'

module Familia
  class EncryptedFieldType < FieldType
    attr_reader :aad_fields, :key_material, :algorithm

    def initialize(name, aad_fields: [], key_material: nil, algorithm: nil, **options)
      # Encrypted fields are not loggable by default for security
      super(name, **options.merge(on_conflict: :raise, loggable: false))
      @aad_fields = Array(aad_fields).freeze
      @key_material = key_material # Proc returning entropy string
      # Optional per-field write-algorithm pin. When nil, writes use the
      # registry's default provider (highest priority available). When set to a
      # registered algorithm identifier (e.g. 'aes-256-gcm', 'xchacha20poly1305')
      # every write from this field is encrypted with that algorithm regardless
      # of the default. Reads are unaffected -- the provider is always resolved
      # from the stored envelope's own algorithm field -- so pinning changes
      # only the write side and never breaks ciphertext already at rest.
      # Validated lazily: an unregistered algorithm raises Familia::EncryptionError
      # on the first write, not at field declaration.
      @algorithm = algorithm
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
          elsif value.is_a?(Familia::Encryption::StoredEnvelope)
            # Rehydrated from storage (load, find_by_id, refresh!). Provenance,
            # not shape, earns the verbatim path: #deserialize is the only place
            # that wraps values in StoredEnvelope, so nothing a caller assigns
            # reaches this branch by looking like an envelope (#405).
            instance_variable_set(:"@#{field_name}", field_type.conceal_stored(self, value))
          else
            # Plaintext -- including anything that merely looks like an
            # envelope. Encrypt and wrap in ConcealedString.
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
                  "Context isolation violation: encrypted field '#{field_name}' accessed from " \
                  "#{self.class.name}:#{field_name}:#{identifier} but was encrypted for " \
                  "#{concealed.context_description}"
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

    def encrypt_value(record, value)
      context = build_context(record)
      additional_data = build_aad(record)
      entropy = build_key_material(record)
      context = context_with_entropy(context, entropy)

      # A per-field @algorithm pins the write algorithm via encrypt_with;
      # otherwise the default provider (registry priority) is used. Either path
      # records the chosen algorithm in the envelope, so the read path stays
      # self-describing and unpinning/repinning never affects existing data.
      result = if @algorithm
        Familia::Encryption.encrypt_with(@algorithm, value, context: context, additional_data: additional_data)
      else
        Familia::Encryption.encrypt(value, context: context, additional_data: additional_data)
      end

      Familia::Encryption::EncryptedData.from_json(result).with_metadata(
        envelope_version: 2,
        aad_fields: @aad_fields.empty? ? nil : @aad_fields.map(&:to_s),
        key_material_fields: entropy ? ['key_material'] : nil
      ).to_json
    end

    def decrypt_value(record, encrypted)
      envelope = Familia::Encryption::EncryptedData.from_json(encrypted)
      context = build_context(record)

      if envelope.envelope_version && envelope.envelope_version >= 2
        # v2 envelopes are self-describing: a nil stored_aad_fields means the
        # value was encrypted with no AAD fields. Fall back to [] (not the
        # current class-level @aad_fields) so that adding aad_fields to a model
        # later cannot break decryption of already-stored v2 envelopes.
        additional_data = build_aad(record, fields: envelope.stored_aad_fields || [])
        context = context_with_entropy(context, build_key_material(record)) if envelope.has_key_material?
      else
        additional_data = build_aad(record)
      end

      Familia::Encryption.decrypt(encrypted, context: context, additional_data: additional_data)
    end

    def persistent?
      true
    end

    def category
      :encrypted
    end

    # Storage hook (FieldType#deserialize): mark the value as having come from
    # storage so the setter can take it verbatim. Horreum calls this only while
    # hydrating an object from its hash, never for values assigned by callers,
    # which is what makes the marker a provenance signal rather than a shape
    # check (#405).
    #
    # @param value [Hash, String, nil] The decoded stored value
    # @return [Familia::Encryption::StoredEnvelope, nil]
    #
    def deserialize(value, _record = nil)
      return nil if value.nil?

      Familia::Encryption::StoredEnvelope.new(payload: value)
    end

    # Wrap a value rehydrated from storage for the given record.
    #
    # The payload is normally the parsed envelope (deserialize_value returns
    # a Hash), which is re-serialized to its canonical JSON string and wrapped
    # without re-encrypting. A payload that is not an envelope at all is a
    # legacy plaintext value already at rest in this slot; it is encrypted in
    # memory so the next save protects it, as before.
    #
    # @param record [Familia::Horreum] The record being hydrated
    # @param stored_envelope [Familia::Encryption::StoredEnvelope]
    # @return [ConcealedString, nil]
    #
    def conceal_stored(record, stored_envelope)
      stored = stored_envelope.payload
      return nil if stored.nil? || (stored.is_a?(::String) && stored.empty?)

      encrypted = if encrypted_json?(stored)
        stored.is_a?(Hash) ? Familia::JsonSerializer.dump(stored) : stored
      else
        encrypt_value(record, stored)
      end

      ConcealedString.new(encrypted, record, self)
    end

    # Shape check: does this value parse as an encryption envelope? Used to
    # validate what came back from storage. It is deliberately NOT how the
    # setter decides whether to encrypt -- that is decided by provenance via
    # StoredEnvelope (#405), because any caller can produce this shape.
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

    def build_context(record)
      "#{record.class.name}:#{@name}:#{record.identifier}"
    end

    def context_with_entropy(context, entropy)
      entropy ? "#{context}:#{entropy}" : context
    end

    # Extract raw value from RedactedString or coerce via .to_s.
    # nil.to_s → "" preserves fixed AAD join positions.
    def unwrap_value(value)
      value.is_a?(::RedactedString) ? value.value : value.to_s
    end

    def build_key_material(record)
      return nil unless @key_material

      result = @key_material.call(record)
      return nil if result.nil?

      unwrap_value(result)
    end

    # Build AAD binding ciphertext to record context and optional field values.
    def build_aad(record, fields: @aad_fields)
      identifier = record.identifier
      return nil if identifier.nil? || identifier.to_s.empty?

      base_components = [record.class.name, @name, identifier]

      if fields.empty?
        base_components.join(':')
      else
        values = fields.map { |field| unwrap_value(record.send(field)) }
        all_components = [*base_components, *values]
        Digest::SHA256.hexdigest(all_components.join(':'))
      end
    end
  end
end
