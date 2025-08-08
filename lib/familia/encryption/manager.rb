# lib/familia/encryption/manager.rb

module Familia
  module Encryption
    # High-level encryption manager - replaces monolithic Encryption module
    class Manager
      attr_reader :provider

      def initialize(algorithm: nil)
        Registry.setup! if Registry.providers.empty?
        @provider = algorithm ? Registry.get(algorithm) : Registry.default_provider
        raise EncryptionError, 'No encryption provider available' unless @provider
      end

      def encrypt(plaintext, context:, additional_data: nil)
        return nil if plaintext.to_s.empty?

        key = derive_key(context)

        result = @provider.encrypt(plaintext, key, additional_data)

        Familia::Encryption::EncryptedData.new(
          algorithm: @provider.algorithm,
          nonce: Base64.strict_encode64(result[:nonce]),
          ciphertext: Base64.strict_encode64(result[:ciphertext]),
          auth_tag: Base64.strict_encode64(result[:auth_tag]),
          key_version: current_key_version
        ).to_h.to_json
      ensure
        Familia::Encryption.secure_wipe(key) if key
      end

      def decrypt(encrypted_json, context:, additional_data: nil)
        return nil if encrypted_json.nil? || encrypted_json.empty?

        begin
          data = Familia::Encryption::EncryptedData.new(**JSON.parse(encrypted_json, symbolize_names: true))

          # Validate algorithm support
          provider = Registry.get(data.algorithm)
          key = derive_key(context, version: data.key_version)

          # Safely decode and validate sizes
          nonce = decode_and_validate(data.nonce, provider.nonce_size, 'nonce')
          ciphertext = Base64.strict_decode64(data.ciphertext)
          auth_tag = decode_and_validate(data.auth_tag, provider.auth_tag_size, 'auth_tag')

          provider.decrypt(ciphertext, key, nonce, auth_tag, additional_data)
        rescue EncryptionError
          raise
        rescue StandardError
          raise EncryptionError, 'Decryption failed'
        end
      ensure
        Familia::Encryption.secure_wipe(key) if key
      end

      private

      def decode_and_validate(encoded, expected_size, component)
        decoded = Base64.strict_decode64(encoded)
        raise EncryptionError, 'Invalid encrypted data' unless decoded.bytesize == expected_size
        decoded
      end

      def derive_key(context, version: nil)
        # Increment counter to prove no caching is happening
        Familia::Encryption.derivation_count.increment

        version ||= current_key_version
        master_key = get_master_key(version)

        @provider.derive_key(master_key, context)
      ensure
        Familia::Encryption.secure_wipe(master_key) if master_key
      end

      def get_master_key(version)
        raise EncryptionError, 'Key version cannot be nil' if version.nil?

        key = encryption_keys[version] || encryption_keys[version.to_sym] || encryption_keys[version.to_s]
        raise EncryptionError, "No key for version: #{version}" unless key

        Base64.strict_decode64(key)
      end

      def encryption_keys
        Familia.config.encryption_keys || {}
      end

      def current_key_version
        Familia.config.current_key_version
      end
    end
  end
end
