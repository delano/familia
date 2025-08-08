# lib/familia/encryption/providers/xchacha20_poly1305_provider.rb

module Familia
  module Encryption
    module Providers
      class XChaCha20Poly1305Provider < Provider
        ALGORITHM = 'xchacha20poly1305'.freeze
        NONCE_SIZE = 24
        AUTH_TAG_SIZE = 16

        def self.available?
          defined?(RbNaCl)
        end

        def self.priority
          100 # Highest priority - best in class
        end

        def encrypt(plaintext, key, additional_data = nil)
          nonce = generate_nonce
          aead_key = key[0..31]
          box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(aead_key)

          aad = additional_data.to_s
          ciphertext_with_tag = box.encrypt(nonce, plaintext.to_s, aad)

          {
            ciphertext: ciphertext_with_tag[0...-16],
            auth_tag: ciphertext_with_tag[-16..-1],
            nonce: nonce
          }
        end

        def decrypt(ciphertext, key, nonce, auth_tag, additional_data = nil)
          aead_key = key[0..31]
          box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(aead_key)

          ciphertext_with_tag = ciphertext + auth_tag
          aad = additional_data.to_s

          box.decrypt(nonce, ciphertext_with_tag, aad)
        rescue RbNaCl::CryptoError
          raise EncryptionError, 'Decryption failed - invalid key or corrupted data'
        end

        def generate_nonce
          RbNaCl::Random.random_bytes(NONCE_SIZE)
        end

        def derive_key(master_key, context)
          RbNaCl::Hash.blake2b(
            context.force_encoding('BINARY'),
            key: master_key[0..31],
            digest_size: 32,
            personal: 'FamiliaE'.ljust(16, "\0")
          )
        end

        def secure_wipe(key)
          RbNaCl::Util.zero(key) if key
        end
      end
    end
  end
end
