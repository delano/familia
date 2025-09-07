# lib/familia/encryption/encrypted_data.rb

module Familia
  module Encryption
    EncryptedData = Data.define(:algorithm, :nonce, :ciphertext, :auth_tag, :key_version) do
      # Class methods for parsing and validation
      def self.valid?(json_string)
        return true if json_string.nil?  # Allow nil values
        return false unless json_string.kind_of?(::String)

        begin
          parsed = Familia::JsonSerializer.parse(json_string, symbolize_names: true)
          return false unless parsed.is_a?(Hash)

          # Check for required fields
          required_fields = [:algorithm, :nonce, :ciphertext, :auth_tag, :key_version]
          result = required_fields.all? { |field| parsed.key?(field) }
          Familia.ld "[valid?] result: #{result}, parsed: #{parsed}, required: #{required_fields}"
          result
        rescue Familia::SerializerError => e
          Familia.ld "[valid?] JSON error: #{e.message}"
          false
        end
      end

      def self.validate!(json_string)
        return nil if json_string.nil?

        unless json_string.kind_of?(::String)
          raise EncryptionError, "Expected JSON string, got #{json_string.class}"
        end

        begin
          parsed = Familia::JsonSerializer.parse(json_string, symbolize_names: true)
        rescue Familia::SerializerError => e
          raise EncryptionError, "Invalid JSON structure: #{e.message}"
        end

        unless parsed.is_a?(Hash)
          raise EncryptionError, "Expected JSON object, got #{parsed.class}"
        end

        required_fields = [:algorithm, :nonce, :ciphertext, :auth_tag, :key_version]
        missing_fields = required_fields.reject { |field| parsed.key?(field) }

        unless missing_fields.empty?
          raise EncryptionError, "Missing required fields: #{missing_fields.join(', ')}"
        end

        new(**parsed)
      end

      def self.from_json(json_string)
        validate!(json_string)
      end

      # Instance methods for decryptability validation
      def decryptable?
        return false unless algorithm && nonce && ciphertext && auth_tag && key_version

        # Ensure Registry is set up before checking algorithms
        Registry.setup! if Registry.providers.empty?

        # Check if algorithm is supported
        return false unless Registry.providers.key?(algorithm)

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
        unless algorithm
          raise EncryptionError, "Missing algorithm field"
        end

        # Ensure Registry is set up before checking algorithms
        Registry.setup! if Registry.providers.empty?

        unless Registry.providers.key?(algorithm)
          raise EncryptionError, "Unsupported algorithm: #{algorithm}"
        end

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
          raise EncryptionError, "Invalid Base64 encoding in nonce field"
        end

        begin
          Base64.strict_decode64(ciphertext)  # ciphertext can be variable size
        rescue ArgumentError
          raise EncryptionError, "Invalid Base64 encoding in ciphertext field"
        end

        begin
          decoded_auth_tag = Base64.strict_decode64(auth_tag)
          if decoded_auth_tag.bytesize != provider.auth_tag_size
            raise EncryptionError, "Invalid auth_tag size: expected #{provider.auth_tag_size}, got #{decoded_auth_tag.bytesize}"
          end
        rescue ArgumentError
          raise EncryptionError, "Invalid Base64 encoding in auth_tag field"
        end

        # Validate that the key version exists
        unless Familia.config.encryption_keys&.key?(key_version.to_sym)
          raise EncryptionError, "No key for version: #{key_version}"
        end

        self
      end
    end
  end
end
