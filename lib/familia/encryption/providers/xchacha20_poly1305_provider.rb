# lib/familia/encryption/providers/xchacha20_poly1305_provider.rb

# ⚠️  RUBY MEMORY SAFETY WARNING ⚠️
#
# This encryption provider, like all Ruby-based cryptographic implementations,
# stores secrets (keys, plaintext, derived keys) as Ruby strings in memory.
#
# SECURITY IMPLICATIONS:
# - Keys remain in memory after use (garbage collection timing is unpredictable)
# - Ruby strings cannot be securely wiped from memory
# - Memory dumps may contain cryptographic secrets
# - Swap files may persist secrets to disk
# - String operations create copies that persist in memory
#
# Ruby provides NO memory safety guarantees for cryptographic secrets.
#
# For production systems handling sensitive data, consider:
# - Hardware Security Modules (HSMs)
# - External key management services
# - Languages with manual memory management
# - Cryptographic appliances with secure memory

begin
  require 'rbnacl'
rescue LoadError
  # RbNaCl not available - provider will report as unavailable
  # To add: gem 'rbnacl', '~> 7.1', '>= 7.1.1'
end

module Familia
  module Encryption
    module Providers
      class XChaCha20Poly1305Provider < Provider
        ALGORITHM = 'xchacha20poly1305'.freeze
        NONCE_SIZE = 24
        AUTH_TAG_SIZE = 16

        def self.available?
          !!defined?(RbNaCl)
        end

        def self.priority
          100 # Highest priority - best in class
        end

        def encrypt(plaintext, key, additional_data = nil)
          validate_key_length!(key)
          nonce = generate_nonce
          box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(key)

          aad = additional_data.to_s
          ciphertext_with_tag = box.encrypt(nonce, plaintext.to_s, aad)

          {
            ciphertext: ciphertext_with_tag[0...-16],
            auth_tag: ciphertext_with_tag[-16..-1],
            nonce: nonce
          }
        end

        def decrypt(ciphertext, key, nonce, auth_tag, additional_data = nil)
          validate_key_length!(key)
          box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(key)

          ciphertext_with_tag = ciphertext + auth_tag
          aad = additional_data.to_s

          box.decrypt(nonce, ciphertext_with_tag, aad)
        rescue RbNaCl::CryptoError
          raise EncryptionError, 'Decryption failed - invalid key or corrupted data'
        end

        def generate_nonce
          RbNaCl::Random.random_bytes(NONCE_SIZE)
        end

        # Derives a context-specific encryption key using BLAKE2b.
        #
        # The personalization parameter provides cryptographic domain separation,
        # ensuring that derived keys are unique per application even when using
        # identical master keys and contexts. This prevents key reuse across
        # different applications or library versions.
        #
        # @param master_key [String] The master key (must be >= 32 bytes)
        # @param context [String] Context string for key derivation
        # @param personal [String, nil] Optional personalization override
        # @return [String] 32-byte derived key
        def derive_key(master_key, context, personal: nil)
          validate_key_length!(master_key)
          raw_personal = personal || Familia.config.encryption_personalization
          if raw_personal.include?("\0")
            raise EncryptionError, 'Personalization string must not contain null bytes'
          end
          personal_string = raw_personal.ljust(16, "\0")

          RbNaCl::Hash.blake2b(
            context.force_encoding('BINARY'),
            key: master_key,
            digest_size: 32,
            personal: personal_string
          )
        end

        # Clear key from memory (no security guarantees in Ruby)
        def secure_wipe(key)
          key&.clear
        end

        private

        def validate_key_length!(key)
          raise EncryptionError, 'Key cannot be nil' if key.nil?
          raise EncryptionError, 'Key must be at least 32 bytes' if key.bytesize < 32
        end
      end
    end
  end
end
