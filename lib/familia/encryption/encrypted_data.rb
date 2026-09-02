# lib/familia/encryption/encrypted_data.rb
#
# frozen_string_literal: true

module Familia
  module Encryption
    # Encoding names an envelope may carry. The write path records
    # `plaintext.encoding.name`, so every legitimate value is a canonical
    # Ruby encoding name (aliases are accepted too). The special names
    # "locale", "external", "internal" and "filesystem" are excluded: they
    # resolve differently per host, are never written, and would let a
    # tampered envelope pick the encoding of whatever machine reads it.
    #
    # The field is not covered by the AEAD tag, so this allowlist is what
    # stands between a rewritten `encoding` and force_encoding raising
    # ArgumentError/TypeError inside the decrypt path (#408).
    ENVELOPE_ENCODINGS = (Encoding.name_list - %w[locale external internal filesystem]).freeze

    EncryptedData = Data.define(:algorithm, :nonce, :ciphertext, :auth_tag, :key_version, :encoding, :envelope_version,
:aad_fields, :key_material_fields) do
      def initialize(algorithm:, nonce:, ciphertext:, auth_tag:, key_version:, encoding: nil, envelope_version: nil,
                     aad_fields: nil, key_material_fields: nil)
        super
      end

      # Omit nil-valued keys from the hash representation so that
      # the encrypted envelope stays backward-compatible (no :encoding
      # key unless explicitly set).
      def to_h
        super.compact
      end

      def to_json(*_args)
        Familia::JsonSerializer.dump(to_h)
      end

      def with_metadata(envelope_version: self.envelope_version, aad_fields: self.aad_fields,
                         key_material_fields: self.key_material_fields)
        # EncryptedData is a Data.define, so #with copies all other members
        # for us; only the envelope metadata is overridden here.
        with(
          envelope_version: envelope_version,
          aad_fields: aad_fields,
          key_material_fields: key_material_fields
        )
      end

      def has_key_material?
        !key_material_fields.nil? && !key_material_fields.empty?
      end

      def stored_aad_fields
        aad_fields&.map(&:to_sym)
      end

      # Class methods for parsing and validation
      def self.valid?(json_string)
        return true if json_string.nil? # Allow nil values
        return false unless json_string.is_a?(::String)

        begin
          parsed = Familia::JsonSerializer.parse(json_string, symbolize_names: true)
          return false unless parsed.is_a?(Hash)

          # Check for required fields
          required_fields = %i[algorithm nonce ciphertext auth_tag key_version]
          result = required_fields.all? { |field| parsed.key?(field) }
          Familia.debug "[valid?] result: #{result}, parsed: #{parsed}, required: #{required_fields}"
          result
        rescue Familia::SerializerError => e
          Familia.debug "[valid?] JSON error: #{e.message}"
          false
        end
      end

      def self.validate!(json_string)
        return nil if json_string.nil?

        raise EncryptionError, "Expected JSON string, got #{json_string.class}" unless json_string.is_a?(::String)

        begin
          parsed = Familia::JsonSerializer.parse(json_string, symbolize_names: true)
        rescue Familia::SerializerError => e
          raise EncryptionError, "Invalid JSON structure: #{e.message}"
        end

        raise EncryptionError, "Expected JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

        required_fields = %i[algorithm nonce ciphertext auth_tag key_version]
        missing_fields = required_fields.reject { |field| parsed.key?(field) }

        raise EncryptionError, "Missing required fields: #{missing_fields.join(', ')}" unless missing_fields.empty?

        new(**parsed.slice(*members))
      end

      def self.from_json(json_string_or_hash)
        # Support both JSON strings (legacy) and already-parsed Hashes (v2.0 deserialization)
        if json_string_or_hash.is_a?(Hash)
          # Already parsed - use directly
          parsed = json_string_or_hash
          # Symbolize keys if they're strings
          parsed = parsed.transform_keys(&:to_sym) if parsed.keys.first.is_a?(String)
          new(**parsed.slice(*members))
        else
          # JSON string - validate and parse
          validate!(json_string_or_hash)
        end
      end

      # Instance methods for decryptability validation
      def decryptable?
        return false unless algorithm && nonce && ciphertext && auth_tag && key_version

        # Ensure Registry is set up before checking algorithms
        Registry.setup! if Registry.providers.empty?

        # Check if algorithm is supported
        return false unless Registry.providers.key?(algorithm)

        return false unless encoding_valid?

        # Validate Base64 encoding of binary fields
        begin
          Base64.strict_decode64(nonce)
          Base64.strict_decode64(ciphertext)
          Base64.strict_decode64(auth_tag)
        rescue ArgumentError
          return false
        end

        true
      end

      def validate_decryptable!
        raise EncryptionError, 'Missing algorithm field' unless algorithm

        # Ensure Registry is set up before checking algorithms
        Registry.setup! if Registry.providers.empty?

        raise EncryptionError, "Unsupported algorithm: #{algorithm}" unless Registry.providers.key?(algorithm)

        unless nonce && ciphertext && auth_tag && key_version
          missing = []
          missing << 'nonce' unless nonce
          missing << 'ciphertext' unless ciphertext
          missing << 'auth_tag' unless auth_tag
          missing << 'key_version' unless key_version
          raise EncryptionError, "Missing required fields: #{missing.join(', ')}"
        end

        # Get the provider for size validation
        provider = Registry.providers[algorithm]

        # Validate Base64 encoding and sizes
        begin
          decoded_nonce = Base64.strict_decode64(nonce)
          if decoded_nonce.bytesize != provider.nonce_size
            raise EncryptionError, "Invalid nonce size: expected #{provider.nonce_size}, got #{decoded_nonce.bytesize}"
          end
        rescue ArgumentError
          raise EncryptionError, 'Invalid Base64 encoding in nonce field'
        end

        begin
          Base64.strict_decode64(ciphertext) # ciphertext can be variable size
        rescue ArgumentError
          raise EncryptionError, 'Invalid Base64 encoding in ciphertext field'
        end

        begin
          decoded_auth_tag = Base64.strict_decode64(auth_tag)
          if decoded_auth_tag.bytesize != provider.auth_tag_size
            raise EncryptionError,
                  "Invalid auth_tag size: expected #{provider.auth_tag_size}, got #{decoded_auth_tag.bytesize}"
          end
        rescue ArgumentError
          raise EncryptionError, 'Invalid Base64 encoding in auth_tag field'
        end

        # Validate that the key version exists
        unless Familia.config.encryption_keys&.key?(key_version.to_sym)
          raise EncryptionError, "No key for version: #{key_version}"
        end

        validate_encoding!
      end

      # The encoding field is optional (pre-#229 envelopes omit it and decrypt
      # as UTF-8). When present it must be a String naming an encoding this
      # Ruby knows, see ENVELOPE_ENCODINGS.
      def encoding_valid?
        encoding.nil? || (encoding.is_a?(::String) && ENVELOPE_ENCODINGS.include?(encoding))
      end

      # @raise [EncryptionError] when the encoding field is present but not a
      #   known encoding name. Raised as a defined error so it can never be
      #   mistaken for corrupted ciphertext (#408).
      def validate_encoding!
        return self if encoding_valid?

        raise EncryptionError, "Unsupported encoding: #{encoding.inspect}"
      end
    end
  end
end
