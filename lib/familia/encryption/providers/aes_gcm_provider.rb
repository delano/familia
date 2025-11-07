# lib/familia/encryption/providers/aes_gcm_provider.rb
#
# frozen_string_literal: true

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

module Familia
  module Encryption
    module Providers
      class AESGCMProvider < Provider
        ALGORITHM = 'aes-256-gcm'.freeze
        NONCE_SIZE = 12
        AUTH_TAG_SIZE = 16

        def self.available?
          true # OpenSSL is always available
        end

        def self.priority
          50 # Fallback option
        end

        def encrypt(plaintext, key, additional_data = nil)
          validate_key_length!(key)
          nonce = generate_nonce
          cipher = create_cipher(:encrypt)
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_data = additional_data.to_s if additional_data

          ciphertext = cipher.update(plaintext.to_s) + cipher.final

          {
            ciphertext: ciphertext,
            auth_tag: cipher.auth_tag,
            nonce: nonce,
          }
        end

        def decrypt(ciphertext, key, nonce, auth_tag, additional_data = nil)
          validate_key_length!(key)
          cipher = create_cipher(:decrypt)
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_tag = auth_tag
          cipher.auth_data = additional_data.to_s if additional_data

          cipher.update(ciphertext) + cipher.final
        rescue OpenSSL::Cipher::CipherError
          raise EncryptionError, 'Decryption failed - invalid key or corrupted data'
        end

        def generate_nonce
          OpenSSL::Random.random_bytes(NONCE_SIZE)
        end

        def derive_key(master_key, context, personal: nil)
          validate_key_length!(master_key)
          info = personal ? "#{context}:#{personal}" : context
          OpenSSL::KDF.hkdf(
            master_key,
            salt: 'FamiliaEncryption',
            info: info,
            length: 32,
            hash: 'SHA256'
          )
        end

        # Clear key from memory (no security guarantees in Ruby)
        def secure_wipe(key)
          key&.clear
        end

        def self.nonce_size
          NONCE_SIZE
        end

        def self.auth_tag_size
          AUTH_TAG_SIZE
        end

        def nonce_size
          NONCE_SIZE
        end

        def auth_tag_size
          AUTH_TAG_SIZE
        end

        def algorithm
          ALGORITHM
        end

        private

        def create_cipher(mode)
          OpenSSL::Cipher.new('aes-256-gcm').tap { |c| c.public_send(mode) }
        end

        def validate_key_length!(key)
          raise EncryptionError, 'Key cannot be nil' if key.nil?
          raise EncryptionError, 'Key must be at least 32 bytes' if key.bytesize < 32
        end
      end
    end
  end
end
