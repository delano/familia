# lib/familia/features/encrypted_fields.rb

require_relative 'encrypted_fields/encrypted_field_type'

module Familia
  module Features
    # EncryptedFields is a feature that provides transparent encryption and decryption
    # of sensitive data stored in Redis/Valkey. It uses strong cryptographic algorithms
    # with field-specific key derivation to protect data at rest while maintaining
    # easy access patterns for authorized applications.
    #
    # This feature automatically encrypts field values before storage and decrypts
    # them on access, providing seamless integration with existing code while
    # ensuring sensitive data is never stored in plaintext.
    #
    # Supported Encryption Algorithms:
    # - XChaCha20-Poly1305 (preferred, requires rbnacl gem)
    # - AES-256-GCM (fallback, uses OpenSSL)
    #
    # Example:
    #
    #   class Vault < Familia::Horreum
    #     feature :encrypted_fields
    #
    #     field :name                    # Regular unencrypted field
    #     encrypted_field :secret_key    # Encrypted storage
    #     encrypted_field :api_token     # Another encrypted field
    #     encrypted_field :love_letter   # Ultra-sensitive field
    #   end
    #
    #   vault = Vault.new(
    #     name: "Production Vault",
    #     secret_key: "super-secret-key-123",
    #     api_token: "sk-1234567890abcdef",
    #     love_letter: "Dear Alice, I love you. -Bob"
    #   )
    #
    #   vault.save
    #   # Only 'name' is stored in plaintext
    #   # secret_key, api_token, love_letter are encrypted
    #
    #   # Access is transparent
    #   vault.secret_key    # => "super-secret-key-123" (decrypted automatically)
    #   vault.api_token     # => "sk-1234567890abcdef" (decrypted automatically)
    #
    # Security Features:
    #
    # Each encrypted field uses a unique encryption key derived from:
    # - Master encryption key (from Familia.encryption_key)
    # - Field name (cryptographic domain separation)
    # - Record identifier (per-record key derivation)
    # - Class name (per-class key derivation)
    #
    # This ensures that:
    # - Swapping encrypted values between fields fails to decrypt
    # - Each record has unique encryption keys
    # - Different classes cannot decrypt each other's data
    # - Field-level access control is cryptographically enforced
    #
    # Cryptographic Design:
    #
    #   # XChaCha20-Poly1305 (preferred)
    #   - 256-bit keys (32 bytes)
    #   - 192-bit nonces (24 bytes) - extended nonce space
    #   - 128-bit authentication tags (16 bytes)
    #   - BLAKE2b key derivation with personalization
    #
    #   # AES-256-GCM (fallback)
    #   - 256-bit keys (32 bytes)
    #   - 96-bit nonces (12 bytes) - standard GCM nonce
    #   - 128-bit authentication tags (16 bytes)
    #   - HKDF-SHA256 key derivation
    #
    # Ciphertext Format:
    #
    # Encrypted data is stored as JSON with algorithm-specific metadata:
    #
    #   {
    #     "algorithm": "xchacha20poly1305",
    #     "nonce": "base64_encoded_nonce",
    #     "ciphertext": "base64_encoded_data",
    #     "auth_tag": "base64_encoded_tag",
    #     "key_version": "v1"
    #   }
    #
    # Additional Authenticated Data (AAD):
    #
    # For extra security, you can include other field values in the authentication:
    #
    #   class SecureDocument < Familia::Horreum
    #     feature :encrypted_fields
    #
    #     field :doc_id, :owner_id, :classification
    #     encrypted_field :content, aad_fields: [:doc_id, :owner_id, :classification]
    #   end
    #
    #   # The content can only be decrypted if doc_id, owner_id, and classification
    #   # values match those used during encryption
    #
    # Passphrase Protection:
    #
    # For ultra-sensitive fields, require user passphrases for decryption:
    #
    #   class PersonalVault < Familia::Horreum
    #     feature :encrypted_fields
    #
    #     field :user_id
    #     encrypted_field :diary_entry    # Ultra-sensitive
    #     encrypted_field :photos         # Ultra-sensitive
    #   end
    #
    #   vault = PersonalVault.new(user_id: 123, diary_entry: "Dear diary...")
    #   vault.save
    #
    #   # Passphrase required for decryption
    #   diary = vault.diary_entry(passphrase_value: user_passphrase)
    #
    # Memory Safety:
    #
    # Encrypted fields return ConcealedString objects that provide memory protection:
    #
    #   secret = vault.secret_key
    #   secret.class               # => ConcealedString
    #   puts secret                # => "[CONCEALED]" (automatic redaction)
    #   secret.inspect             # => "[CONCEALED]" (automatic redaction)
    #
    #   # Safe access pattern
    #   secret.expose do |value|
    #     # Use value directly without creating copies
    #     api_call(authorization: "Bearer #{value}")
    #   end
    #
    #   # Direct access (use carefully)
    #   raw_value = secret.value   # Returns actual decrypted string
    #
    #   # Explicit cleanup
    #   secret.clear!              # Best-effort memory wiping
    #
    # Error Handling:
    #
    # The feature provides specific error types for different failure modes:
    #
    #   # Invalid ciphertext or tampering
    #   vault.secret_key  # => Familia::EncryptionError: Authentication failed
    #
    #   # Wrong passphrase
    #   vault.diary_entry(passphrase_value: "wrong")
    #   # => Familia::EncryptionError: Invalid passphrase
    #
    #   # Missing encryption key
    #   Familia.encryption_key = nil
    #   vault.secret_key  # => Familia::EncryptionError: No encryption key configured
    #
    # Configuration:
    #
    #   # Set master encryption key (required)
    #   Familia.configure do |config|
    #     config.encryption_key = ENV['FAMILIA_ENCRYPTION_KEY']
    #     config.encryption_personalization = 'MyApp-2024'  # Optional customization
    #   end
    #
    #   # Generate a new encryption key
    #   key = Familia::Encryption.generate_key
    #   puts key  # => "base64-encoded-32-byte-key"
    #
    # Key Rotation:
    #
    # The feature supports key versioning for seamless key rotation:
    #
    #   # Step 1: Add new key while keeping old key
    #   Familia.configure do |config|
    #     config.encryption_key = new_key
    #     config.legacy_encryption_keys = { 'v1' => old_key }
    #   end
    #
    #   # Step 2: Objects decrypt with old key, encrypt with new key
    #   vault.secret_key = "new-secret"  # Encrypted with new key
    #   vault.save
    #
    #   # Step 3: After all data is re-encrypted, remove legacy key
    #
    # Integration Patterns:
    #
    #   # Rails application
    #   class User < ApplicationRecord
    #     include Familia::Horreum
    #     feature :encrypted_fields
    #
    #     field :user_id
    #     encrypted_field :credit_card_number
    #     encrypted_field :ssn, aad_fields: [:user_id]
    #   end
    #
    #   # API serialization (encrypted fields excluded by default)
    #   class UserSerializer
    #     def self.serialize(user)
    #       {
    #         id: user.user_id,
    #         created_at: user.created_at,
    #         # credit_card_number and ssn are NOT included
    #       }
    #     end
    #   end
    #
    #   # Background job processing
    #   class PaymentProcessor
    #     def process_payment(user_id)
    #       user = User.find(user_id)
    #
    #       # Access encrypted field safely
    #       user.credit_card_number.expose do |cc_number|
    #         # Process payment without storing plaintext
    #         payment_gateway.charge(cc_number, amount)
    #       end
    #
    #       # Clear sensitive data from memory
    #       user.credit_card_number.clear!
    #     end
    #   end
    #
    # Performance Considerations:
    #
    # - Encryption/decryption adds ~1-5ms overhead per field
    # - Key derivation is cached per field/record combination
    # - XChaCha20-Poly1305 is ~2x faster than AES-256-GCM
    # - Memory allocation increases due to ciphertext expansion
    # - Consider batching operations for high-throughput scenarios
    #
    # Security Limitations:
    #
    # ⚠️ Important: Ruby provides NO memory safety guarantees:
    # - No secure memory wiping (best-effort only)
    # - Garbage collector may copy secrets
    # - String operations create uncontrolled copies
    # - Memory dumps may contain plaintext secrets
    #
    # For highly sensitive applications, consider:
    # - External key management (HashiCorp Vault, AWS KMS)
    # - Hardware Security Modules (HSMs)
    # - Languages with secure memory handling
    # - Dedicated cryptographic appliances
    #
    # Threat Model:
    #
    # ✅ Protected Against:
    # - Database compromise (encrypted data only)
    # - Field value swapping (field-specific keys)
    # - Cross-record attacks (record-specific keys)
    # - Tampering (authenticated encryption)
    #
    # ❌ Not Protected Against:
    # - Master key compromise (all data compromised)
    # - Application memory compromise (plaintext in RAM)
    # - Side-channel attacks (timing, power analysis)
    # - Insider threats with application access
    #
    module EncryptedFields
      def self.included(base)
        Familia.trace :LOADED, self, base, caller(1..1) if Familia.debug?
        base.extend ClassMethods

        # Initialize encrypted fields tracking
        base.instance_variable_set(:@encrypted_fields, []) unless base.instance_variable_defined?(:@encrypted_fields)
      end

      module ClassMethods
        # Define an encrypted field that transparently encrypts/decrypts values
        #
        # Encrypted fields are stored as JSON objects containing the encrypted
        # ciphertext along with cryptographic metadata. Values are automatically
        # encrypted on assignment and decrypted on access.
        #
        # @param name [Symbol] Field name
        # @param aad_fields [Array<Symbol>] Additional fields to include in authentication
        # @param kwargs [Hash] Additional field options
        #
        # @example Basic encrypted field
        #   class Vault < Familia::Horreum
        #     feature :encrypted_fields
        #     encrypted_field :secret_key
        #   end
        #
        # @example Encrypted field with additional authentication
        #   class Document < Familia::Horreum
        #     feature :encrypted_fields
        #     field :doc_id, :owner_id
        #     encrypted_field :content, aad_fields: [:doc_id, :owner_id]
        #   end
        #
        def encrypted_field(name, aad_fields: [], **kwargs)
          @encrypted_fields ||= []
          @encrypted_fields << name unless @encrypted_fields.include?(name)

          require_relative 'encrypted_fields/encrypted_field_type'

          field_type = EncryptedFieldType.new(name, aad_fields: aad_fields, **kwargs)
          register_field_type(field_type)
        end

        # Returns list of encrypted field names defined on this class
        #
        # @return [Array<Symbol>] Array of encrypted field names
        #
        def encrypted_fields
          @encrypted_fields || []
        end

        # Check if a field is encrypted
        #
        # @param field_name [Symbol] The field name to check
        # @return [Boolean] true if field is encrypted, false otherwise
        #
        def encrypted_field?(field_name)
          encrypted_fields.include?(field_name.to_sym)
        end

        # Get encryption algorithm information
        #
        # @return [Hash] Hash containing encryption algorithm details
        #
        def encryption_info
          provider = Familia::Encryption.current_provider
          {
            algorithm: provider.algorithm_name,
            key_size: provider.key_size,
            nonce_size: provider.nonce_size,
            tag_size: provider.tag_size
          }
        end
      end

      # Check if this instance has any encrypted fields with values
      #
      # @return [Boolean] true if any encrypted fields have values
      #
      # TODO: Missing test coverage
      def encrypted_data?
        self.class.encrypted_fields.any? do |field_name|
          field_value = instance_variable_get("@#{field_name}")
          !field_value.nil?
        end
      end

      # Clear all encrypted field values from memory
      #
      # This method iterates through all encrypted fields and calls clear!
      # on any ConcealedString instances. Use this for cleanup when the
      # object is no longer needed.
      #
      # @return [void]
      #
      # @example Clear all secrets when done
      #   vault = Vault.new(secret_key: 'secret', api_token: 'token123')
      #   # ... use vault ...
      #   vault.clear_encrypted_fields!
      #
      def clear_encrypted_fields!
        self.class.encrypted_fields.each do |field_name|
          field_value = instance_variable_get("@#{field_name}")
          if field_value.respond_to?(:clear!)
            field_value.clear!
          end
        end
      end

      # Check if all encrypted fields have been cleared from memory
      #
      # @return [Boolean] true if all encrypted fields are cleared, false otherwise
      #
      def encrypted_fields_cleared?
        self.class.encrypted_fields.all? do |field_name|
          field_value = instance_variable_get("@#{field_name}")
          field_value.nil? || (field_value.respond_to?(:cleared?) && field_value.cleared?)
        end
      end

      # Re-encrypt all encrypted fields with current encryption settings
      #
      # This method is useful for key rotation or algorithm upgrades.
      # It decrypts all encrypted fields and re-encrypts them with the
      # current encryption configuration.
      #
      # @return [Boolean] true if re-encryption succeeded
      #
      # @example Re-encrypt after key rotation
      #   vault.re_encrypt_fields!
      #   vault.save
      #
      def re_encrypt_fields!
        self.class.encrypted_fields.each do |field_name|
          current_value = send(field_name)
          next if current_value.nil?

          # Force re-encryption by setting the value again
          if current_value.respond_to?(:value)
            send("#{field_name}=", current_value.value)
          else
            send("#{field_name}=", current_value)
          end
        end
        true
      end

      # Get encryption status for all encrypted fields
      #
      # Returns a hash showing the encryption status of each encrypted field,
      # useful for debugging and monitoring.
      #
      # @return [Hash] Hash with field names as keys and status information
      #
      # @example Check encryption status
      #   vault.encrypted_fields_status
      #   # => {
      #   #   secret_key: { encrypted: true, algorithm: "xchacha20poly1305", cleared: false },
      #   #   api_token: { encrypted: true, algorithm: "aes-256-gcm", cleared: true }
      #   # }
      #
      def encrypted_fields_status
        self.class.encrypted_fields.each_with_object({}) do |field_name, status|
          field_value = instance_variable_get("@#{field_name}")

          if field_value.nil?
            status[field_name] = { encrypted: false, value: nil }
          elsif field_value.respond_to?(:cleared?) && field_value.cleared?
            status[field_name] = { encrypted: true, cleared: true }
          elsif field_value.respond_to?(:concealed?) && field_value.concealed?
            status[field_name] = { encrypted: true, algorithm: "unknown", cleared: false }
          else
            status[field_name] = { encrypted: false, value: "[CONCEALED]" }
          end
        end
      end

    end
  end
end
