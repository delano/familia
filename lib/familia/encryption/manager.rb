# lib/familia/encryption/manager.rb
#
# frozen_string_literal: true

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
        plaintext = plaintext.to_s
        return nil if plaintext.empty?

        key = derive_key(context)

        result = @provider.encrypt(plaintext, key, additional_data)

        encrypted_data = Familia::Encryption::EncryptedData.new(
          algorithm: @provider.algorithm,
          nonce: Base64.strict_encode64(result[:nonce]),
          ciphertext: Base64.strict_encode64(result[:ciphertext]),
          auth_tag: Base64.strict_encode64(result[:auth_tag]),
          key_version: current_key_version,
          encoding: plaintext.encoding.name,
        ).to_h

        Familia::JsonSerializer.dump(encrypted_data)
      ensure
        Familia::Encryption.secure_wipe(key) if key
      end

      def decrypt(encrypted_json_or_hash, context:, additional_data: nil)
        if encrypted_json_or_hash.nil? || (encrypted_json_or_hash.respond_to?(:empty?) && encrypted_json_or_hash.empty?)
          return nil
        end

        # Increment counter immediately to track all decryption attempts, even failed ones
        Familia::Encryption.derivation_count.increment

        begin
          # Delegate parsing and instantiation to EncryptedData.from_json
          # Wrap validation errors for security (don't expose internal structure details)
          begin
            data = Familia::Encryption::EncryptedData.from_json(encrypted_json_or_hash)
            raise EncryptionError, 'Failed to parse encrypted data' unless data
          rescue EncryptionError => e
            # Re-wrap validation errors with generic message for security
            raise EncryptionError, "Decryption failed: #{e.message}"
          end

          # Validate algorithm support
          provider = Registry.get(data.algorithm)

          # Safely decode and validate sizes
          nonce = decode_and_validate(data.nonce, provider.nonce_size, 'nonce')
          ciphertext = decode_and_validate_ciphertext(data.ciphertext)
          auth_tag = decode_and_validate(data.auth_tag, provider.auth_tag_size, 'auth_tag')

          # Try each candidate HKDF salt, current first, so ciphertext written
          # before a salt change still decrypts. Providers without salt rotation
          # expose a single nil "salt" and are attempted exactly once. A wrong
          # salt derives a different key and fails the authenticated decrypt
          # cleanly, so iterating never yields a false positive. See #310 (S2).
          salts = provider.respond_to?(:hkdf_salts) ? provider.hkdf_salts : [nil]
          key = nil
          plaintext = nil
          last_error = nil
          salts.each do |salt|
            key = derive_key_without_increment(context, version: data.key_version, provider: provider, salt: salt)
            begin
              plaintext = provider.decrypt(ciphertext, key, nonce, auth_tag, additional_data)
              break
            rescue EncryptionError => e
              last_error = e
              plaintext = nil
            ensure
              Familia::Encryption.secure_wipe(key)
            end
          end
          raise(last_error || EncryptionError.new('Decryption failed - invalid key or corrupted data')) if plaintext.nil?

          plaintext.force_encoding(data.encoding || 'UTF-8')
        rescue EncryptionError
          raise
        rescue Familia::SerializerError => e
          raise EncryptionError, "Invalid JSON structure: #{e.message}"
        rescue StandardError => e
          raise EncryptionError, "Decryption failed: #{e.message}"
        end
      ensure
        Familia::Encryption.secure_wipe(key) if key
      end

      private

      def decode_and_validate(encoded, expected_size, component)
        decoded = Base64.strict_decode64(encoded)
        raise EncryptionError, 'Invalid encrypted data' unless decoded.bytesize == expected_size

        decoded
      rescue ArgumentError
        raise EncryptionError, "Invalid Base64 encoding in #{component} field"
      end

      def decode_and_validate_ciphertext(encoded)
        Base64.strict_decode64(encoded)
      rescue ArgumentError
        raise EncryptionError, 'Invalid Base64 encoding in ciphertext field'
      end

      def derive_key(context, version: nil, provider: nil)
        # Increment counter to prove no caching is happening
        Familia::Encryption.derivation_count.increment

        derive_key_without_increment(context, version: version, provider: provider)
      end

      def derive_key_without_increment(context, version: nil, provider: nil, salt: nil)
        # Use provided provider or fall back to instance provider
        provider ||= @provider

        # Require explicit provider in decrypt context
        raise EncryptionError, 'Provider required for key derivation' unless provider

        version ||= current_key_version

        # Request-scoped key cache (opt-in via Familia::Encryption.with_request_cache).
        # Disabled by default for maximum security (keys are not held in memory
        # longer than a single derivation). The cache key includes the algorithm
        # so different providers never share a derived key, the version so key
        # rotation stays correct, and the resolved salt so rotated-salt derivations
        # never collide. On a hit we return a copy and never fetch the master key,
        # minimising master-key exposure.
        cache = Fiber[:familia_request_cache] if Fiber[:familia_request_cache_enabled]
        if cache
          # Key on the *resolved* salt, not the raw argument. When salt is nil
          # (the encrypt path) the provider derives with hkdf_salts.first; the
          # decrypt loop later passes that same value explicitly. Keying on the
          # raw argument would file those two identical derivations under
          # different keys (nil vs the resolved salt), so an encrypt followed by a
          # decrypt of the same value in one request would derive twice instead of
          # hitting the cache. Providers without salt rotation have no effective
          # salt (nil), so their cache key is unchanged.
          effective_salt = salt || (provider.respond_to?(:hkdf_salts) ? provider.hkdf_salts.first : nil)
          cache_key = "#{provider.algorithm}:#{version}:#{effective_salt}:#{context}"
          cached = cache[cache_key]
          return cached.dup if cached
        end

        master_key = get_master_key(version)
        # Only forward an explicit salt to providers that accept one (the AES-GCM
        # salt-rotation path). The default derivation keeps the original arity so
        # providers without a salt parameter are unaffected.
        derived = salt.nil? ? provider.derive_key(master_key, context) : provider.derive_key(master_key, context, salt: salt)
        cache[cache_key] = derived.dup if cache
        derived
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
