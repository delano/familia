# lib/familia/encryption.rb

require 'base64'
require 'json'
require 'openssl'

module Familia
  class EncryptionError < StandardError; end

  module Encryption
    EncryptedData = Data.define(:algorithm, :nonce, :ciphertext, :auth_tag, :key_version)

    class << self
      def encrypt(plaintext, context:, additional_data: nil)
        return nil if plaintext.to_s.empty?

        key = derive_key(context)
        nonce = generate_nonce

        cipher = create_cipher(:encrypt)
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_data = additional_data.to_s if additional_data # Ensure string

        ciphertext = cipher.update(plaintext.to_s) + cipher.final

        EncryptedData.new(
          algorithm: 'aes-256-gcm',
          nonce: Base64.strict_encode64(nonce),
          ciphertext: Base64.strict_encode64(ciphertext),
          auth_tag: Base64.strict_encode64(cipher.auth_tag),
          key_version: current_key_version
        ).to_json
      ensure
        secure_wipe(key) if key
      end

      def decrypt(encrypted_json, context:, additional_data: nil)
        return nil if encrypted_json.nil? || encrypted_json.empty?

        data = EncryptedData.new(**JSON.parse(encrypted_json, symbolize_names: true))
        key = derive_key(context, version: data.key_version)

        cipher = create_cipher(:decrypt)
        cipher.key = key
        cipher.iv = Base64.strict_decode64(data.nonce)
        cipher.auth_tag = Base64.strict_decode64(data.auth_tag)
        cipher.auth_data = additional_data.to_s if additional_data # Ensure string

        Base64.strict_decode64(data.ciphertext)
          .then { |ct| cipher.update(ct) + cipher.final }
      rescue JSON::ParserError => e
        raise EncryptionError, "Invalid encrypted data format"
      rescue OpenSSL::Cipher::CipherError => e
        raise EncryptionError, "Decryption failed - invalid key or corrupted data"
      ensure
        secure_wipe(key) if key
      end

      # Validate configuration at startup
      def validate_configuration!
        raise EncryptionError, "No encryption keys configured" if encryption_keys.empty?
        raise EncryptionError, "No current key version set" unless current_key_version

        # Validate current key exists and is valid Base64
        current_key = encryption_keys[current_key_version]
        raise EncryptionError, "Current key version not found: #{current_key_version}" unless current_key

        begin
          Base64.strict_decode64(current_key)
        rescue ArgumentError
          raise EncryptionError, "Current encryption key is not valid Base64"
        end

        # Warn if using OpenSSL instead of libsodium
        unless defined?(RbNaCl)
          warn "WARNING: Using OpenSSL for encryption. Install rbnacl gem for better security."
        end
      end

      private

      def derive_key(context, version: nil)
        version ||= current_key_version
        master_key = get_master_key(version)

        # Cache key for this request/thread
        cache_key = "#{version}:#{context}"
        key_cache.fetch(cache_key) do
          perform_key_derivation(master_key, context)
        end
      end

      def perform_key_derivation(master_key, context)
        if defined?(RbNaCl)
          # Use BLAKE2b with proper domain separation
          RbNaCl::Hash.blake2b(
            context.force_encoding('BINARY'),
            key: master_key[0..31],
            digest_size: 32,
            personal: 'FamiliaE'.ljust(16, "\0") # Domain separator
          )
        else
          # OpenSSL fallback
          OpenSSL::KDF.hkdf(
            master_key,
            salt: 'FamiliaEncryption',
            info: context,
            length: 32,
            hash: 'SHA256'
          )
        end
      end

      def generate_nonce
        if defined?(RbNaCl)
          RbNaCl::Random.random_bytes(12)
        else
          OpenSSL::Random.random_bytes(12)
        end
      end

      def create_cipher(mode)
        OpenSSL::Cipher.new('aes-256-gcm').tap { |c| c.public_send(mode) }
      end

      def secure_wipe(key)
        return unless key

        if defined?(RbNaCl)
          RbNaCl::Util.zero(key)
        elsif key.respond_to?(:clear)
          key.clear  # Ruby 2.5+
        else
          key.replace("\x00" * key.bytesize)
        end
      rescue => e
        # Best effort - don't fail if wiping fails
        nil
      end

      def key_cache
        Thread.current[:familia_key_cache] ||= {}
      end

      def get_master_key(version)
        key = encryption_keys[version]
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
