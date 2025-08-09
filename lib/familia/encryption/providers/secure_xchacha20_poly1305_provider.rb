# lib/familia/encryption/providers/secure_xchacha20_poly1305_provider.rb

# ⚠️  PROTOTYPE IMPLEMENTATION - NOT FOR PRODUCTION USE ⚠️
#
# This provider is a PROTOTYPE demonstrating alternate memory security practices
# for handling secrets in Ruby. It is NOT intended for use with actual sensitive
# data or production systems.
#
# LIMITATIONS:
# - Still relies on Ruby strings internally (unavoidable language constraint)
# - RbNaCl library stores keys as strings regardless of our efforts
# - Ruby's garbage collector behavior cannot be fully controlled
# - No guarantee of complete memory cleanup
#
# This implementation serves as:
# - Educational example of security-conscious programming
# - Research prototype for future FFI-based implementations
# - Demonstration of defense-in-depth techniques
#
# For actual cryptographic applications, consider:
# - Hardware Security Modules (HSMs)
# - Dedicated cryptographic appliances
# - Languages with manual memory management (C, Rust)
# - External key management services

begin
  require 'rbnacl'
  require 'ffi'
rescue LoadError
  # Dependencies not available - provider will report as unavailable
end

module Familia
  module Encryption
    module Providers
      # Enhanced XChaCha20Poly1305Provider with improved memory security
      #
      # While complete avoidance of Ruby strings for secrets is challenging due to
      # RbNaCl's internal implementation, this provider implements several security
      # improvements:
      #
      # 1. Minimizes key lifetime in memory
      # 2. Uses immediate secure wiping after operations
      # 3. Avoids unnecessary key duplication
      # 4. Uses locked memory where possible (future enhancement)
      #
      class SecureXChaCha20Poly1305Provider < Provider
        ALGORITHM = 'xchacha20poly1305-secure'.freeze
        NONCE_SIZE = 24
        AUTH_TAG_SIZE = 16

        def self.available?
          !!defined?(RbNaCl) && !!defined?(FFI)
        end

        def self.priority
          110 # Higher than regular XChaCha20Poly1305Provider
        end

        def encrypt(plaintext, key, additional_data = nil)
          validate_key_length!(key)

          # Generate nonce first to avoid holding onto key longer than necessary
          nonce = generate_nonce

          # Minimize key exposure by performing operation immediately
          result = perform_encryption(plaintext, key, nonce, additional_data)

          # Attempt to clear the key parameter (if mutable)
          secure_wipe(key)

          result
        end

        def decrypt(ciphertext, key, nonce, auth_tag, additional_data = nil)
          validate_key_length!(key)

          # Minimize key exposure by performing operation immediately
          begin
            result = perform_decryption(ciphertext, key, nonce, auth_tag, additional_data)
          ensure
            # Attempt to clear the key parameter (if mutable)
            secure_wipe(key)
          end

          result
        end

        def generate_nonce
          RbNaCl::Random.random_bytes(NONCE_SIZE)
        end

        # Enhanced key derivation with immediate cleanup
        def derive_key(master_key, context, personal: nil)
          validate_key_length!(master_key)

          raw_personal = personal || Familia.config.encryption_personalization
          if raw_personal.include?("\0")
            raise EncryptionError, 'Personalization string must not contain null bytes'
          end

          personal_string = raw_personal.ljust(16, "\0")

          # Perform derivation and immediately clear intermediate values
          derived_key = RbNaCl::Hash.blake2b(
            context.force_encoding('BINARY'),
            key: master_key,
            digest_size: 32,
            personal: personal_string
          )

          # Clear personalization string from memory
          personal_string.clear

          # Return derived key (caller responsible for secure cleanup)
          derived_key
        end

        # Clear key from memory (still no security guarantees in Ruby)
        def secure_wipe(key)
          key&.clear
        end

        private

        def perform_encryption(plaintext, key, nonce, additional_data)
          # Create AEAD instance (this internally copies the key)
          box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(key)

          aad = additional_data.to_s
          ciphertext_with_tag = box.encrypt(nonce, plaintext.to_s, aad)

          result = {
            ciphertext: ciphertext_with_tag[0...-16],
            auth_tag: ciphertext_with_tag[-16..-1],
            nonce: nonce
          }

          # Clear intermediate values
          ciphertext_with_tag.clear

          result
        ensure
          # Clear the AEAD instance's internal key if possible
          clear_aead_instance(box) if box
        end

        def perform_decryption(ciphertext, key, nonce, auth_tag, additional_data)
          # Create AEAD instance (this internally copies the key)
          box = RbNaCl::AEAD::XChaCha20Poly1305IETF.new(key)

          ciphertext_with_tag = ciphertext + auth_tag
          aad = additional_data.to_s

          result = box.decrypt(nonce, ciphertext_with_tag, aad)

          # Clear intermediate values
          ciphertext_with_tag.clear

          result
        rescue RbNaCl::CryptoError
          raise EncryptionError, 'Decryption failed - invalid key or corrupted data'
        ensure
          # Clear the AEAD instance's internal key if possible
          clear_aead_instance(box) if box
        end

        def clear_aead_instance(aead_instance)
          # Attempt to clear RbNaCl's internal key storage
          # This is a best-effort cleanup since RbNaCl stores keys as strings internally
          if aead_instance.instance_variable_defined?(:@key)
            internal_key = aead_instance.instance_variable_get(:@key)
            secure_wipe(internal_key) if internal_key
          end
        end

        def validate_key_length!(key)
          raise EncryptionError, 'Key cannot be nil' if key.nil?
          raise EncryptionError, 'Key must be at least 32 bytes' if key.bytesize < 32
        end
      end
    end
  end
end
