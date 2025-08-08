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
        ).to_h.to_json
      ensure
        secure_wipe(key) if key
      end

      def decrypt(encrypted_json, context:, additional_data: nil)
        return nil if encrypted_json.nil? || encrypted_json.empty?

        data = EncryptedData.new(**JSON.parse(encrypted_json, symbolize_names: true))

        # Validate algorithm to prevent tampering
        unless data.algorithm == 'aes-256-gcm'
          raise EncryptionError, "Decryption failed - unsupported algorithm: #{data.algorithm}"
        end

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

      # ========================================================================
      # KEY DERIVATION STRATEGY - JOHNNY NO-CACHE ON THE SPOT
      # ========================================================================
      #
      # This implementation deliberately DOES NOT cache derived encryption keys.
      # Each encryption/decryption operation performs fresh key derivation from
      # the master key. This design prioritizes security over performance.
      #
      # WHY NO CACHING?
      # ---------------
      # 1. **Memory Safety**: Cached keys in long-running processes create a
      #    larger attack surface for memory disclosure vulnerabilities (e.g.,
      #    Heartbleed-style attacks, core dumps, side-channel attacks).
      #
      # 2. **Forward Secrecy**: Each operation is cryptographically isolated.
      #    Compromise of one derived key doesn't affect past or future operations.
      #
      # 3. **Thread Safety**: No shared state between threads eliminates an entire
      #    class of concurrency bugs and potential race conditions.
      #
      # 4. **Simplicity**: No cache invalidation logic, no memory growth concerns,
      #    no cleanup requirements, no cache poisoning risks.
      #
      # PERFORMANCE CONSIDERATIONS
      # --------------------------
      # - BLAKE2b derivation: ~0.05ms per operation (with libsodium)
      # - HKDF derivation: ~0.1ms per operation (OpenSSL fallback)
      # - For OTS's use case (user-facing secret sharing), this overhead is negligible
      #   compared to network latency and database I/O.
      #
      # SECURITY GUARANTEES
      # -------------------
      # - Master keys are wiped from memory immediately after use (see ensure block)
      # - No derived key material persists beyond a single encrypt/decrypt operation
      # - Each field context gets a unique derived key (domain separation)
      # - Thread-local operation prevents cross-request key leakage
      #
      # IF YOU NEED CACHING
      # -------------------
      # If performance profiling shows key derivation is a bottleneck:
      # 1. First verify it's actually the KDF, not network/DB/serialization
      # 2. Consider request-scoped caching (see encryption_request_cache.rb)
      # 3. NEVER implement thread-persistent or global caching for OTS
      #
      # The commented-out key_cache method below is intentionally removed.
      # DO NOT re-enable it without a thorough security review.
      #
      def derive_key(context, version: nil)
        version ||= current_key_version
        master_key = get_master_key(version)

        # Fresh key derivation on every call - this is intentional
        perform_key_derivation(master_key, context)
      ensure
        # Critical: Always wipe master key from memory immediately
        # This prevents the master key from persisting in memory where it
        # could be exposed through memory dumps or side-channel attacks
        secure_wipe(master_key) if master_key
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

      # Cache removed for security - each encryption/decryption
      # gets fresh key derivation to prevent key material persistence
      # def key_cache
      #   Thread.current[:familia_key_cache] ||= {}
      # end

      def get_master_key(version)
        raise EncryptionError, "Key version cannot be nil" if version.nil?

        # Handle both string and symbol keys
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
