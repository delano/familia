# lib/familia/encryption/providers/aes_gcm_provider.rb

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
          nonce = generate_nonce
          cipher = create_cipher(:encrypt)
          cipher.key = key
          cipher.iv = nonce
          cipher.auth_data = additional_data.to_s if additional_data

          ciphertext = cipher.update(plaintext.to_s) + cipher.final

          {
            ciphertext: ciphertext,
            auth_tag: cipher.auth_tag,
            nonce: nonce
          }
        end

        def decrypt(ciphertext, key, nonce, auth_tag, additional_data = nil)
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

        def derive_key(master_key, context)
          OpenSSL::KDF.hkdf(
            master_key,
            salt: 'FamiliaEncryption',
            info: context,
            length: 32,
            hash: 'SHA256'
          )
        end

        def secure_wipe(key)
          return unless key

          if key.respond_to?(:clear)
            key.clear # Ruby 2.5+
          else
            key.replace("\x00" * key.bytesize)
          end
        rescue StandardError
          nil # Best effort
        end

        private

        def create_cipher(mode)
          OpenSSL::Cipher.new('aes-256-gcm').tap { |c| c.public_send(mode) }
        end
      end
    end
  end
end
