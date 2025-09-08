# lib/familia/encryption.rb

require 'base64'
require 'oj'
require 'openssl'

# Provider system components
require_relative 'encryption/provider'
require_relative 'encryption/providers/xchacha20_poly1305_provider'
require_relative 'encryption/providers/aes_gcm_provider'
require_relative 'encryption/registry'
require_relative 'encryption/manager'
require_relative 'encryption/encrypted_data'

module Familia
  class EncryptionError < StandardError; end

  module Encryption

    # Smart facade with provider selection and field-specific encryption
    #
    # Usage in EncryptedFieldType can now be more flexible:
    #
    #   module Familia
    #     class EncryptedFieldType < FieldType
    #       attr_reader :algorithm  # Optional algorithm override
    #
    #       def initialize(name, aad_fields: [], algorithm: nil, **options)
    #         super(name, **options.merge(on_conflict: :raise))
    #         @aad_fields = Array(aad_fields).freeze
    #         @algorithm = algorithm  # Use specific algorithm for this field
    #       end
    #
    #       def encrypt_value(record, value)
    #         context = build_context(record)
    #         additional_data = build_aad(record)
    #
    #         if @algorithm
    #           # Use specific algorithm for this field
    #           Familia::Encryption.encrypt_with(@algorithm, value,
    #             context: context,
    #             additional_data: additional_data)
    #         else
    #           # Use default best algorithm
    #           Familia::Encryption.encrypt(value,
    #             context: context,
    #             additional_data: additional_data)
    #         end
    #       end
    #
    #       # Decrypt auto-detects algorithm from data, so no change needed
    #       def decrypt_value(record, encrypted)
    #         context = build_context(record)
    #         additional_data = build_aad(record)
    #
    #         Familia::Encryption.decrypt(encrypted,
    #           context: context,
    #           additional_data: additional_data)
    #       end
    #     end
    #   end
    class << self
      # Get or create a manager with specific algorithm
      def manager(algorithm: nil)
        @managers ||= {}
        @managers[algorithm] ||= Manager.new(algorithm: algorithm)
      end

      # Quick encryption with auto-selected best provider
      def encrypt(plaintext, context:, additional_data: nil)
        manager.encrypt(plaintext, context: context, additional_data: additional_data)
      end

      # Quick decryption (auto-detects algorithm from data)
      def decrypt(encrypted_json, context:, additional_data: nil)
        manager.decrypt(encrypted_json, context: context, additional_data: additional_data)
      end

      # Encrypt with specific algorithm
      def encrypt_with(algorithm, plaintext, context:, additional_data: nil)
        manager(algorithm: algorithm).encrypt(
          plaintext,
          context: context,
          additional_data: additional_data
        )
      end

      # Derivation counter for monitoring no-caching behavior
      def derivation_count
        @derivation_count ||= Concurrent::AtomicFixnum.new(0)
      end

      def reset_derivation_count!
        derivation_count.value = 0
      end

      # Clear key from memory (no security guarantees in Ruby)
      def secure_wipe(key)
        key&.clear
      end

      # Get info about current encryption setup
      def status
        Registry.setup! if Registry.providers.empty?

        {
          default_algorithm: Registry.default_provider&.algorithm,
          available_algorithms: Registry.available_algorithms,
          preferred_available: Registry.default_provider&.class&.name,
          using_hardware: hardware_acceleration?,
          key_versions: encryption_keys.keys,
          current_version: current_key_version
        }
      end

      # Check if we're using hardware acceleration
      def hardware_acceleration?
        provider = Registry.default_provider
        provider && provider.class.name.include?('Hardware')
      end

      # Benchmark available providers
      def benchmark(iterations: 1000)
        require 'benchmark'
        test_data = 'x' * 1024 # 1KB test
        context = 'benchmark:test'

        results = {}
        Registry.providers.each do |algo, provider_class|
          next unless provider_class.available?

          mgr = Manager.new(algorithm: algo)
          time = Benchmark.realtime do
            iterations.times do
              encrypted = mgr.encrypt(test_data, context: context)
              mgr.decrypt(encrypted, context: context)
            end
          end

          results[algo] = {
            time: time,
            ops_per_sec: (iterations * 2 / time).round,
            priority: provider_class.priority
          }
        end

        results
      end

      def validate_configuration!
        raise EncryptionError, 'No encryption keys configured' if encryption_keys.empty?
        raise EncryptionError, 'No current key version set' unless current_key_version

        current_key = encryption_keys[current_key_version]
        raise EncryptionError, "Current key version not found: #{current_key_version}" unless current_key

        begin
          Base64.strict_decode64(current_key)
        rescue ArgumentError
          raise EncryptionError, 'Current encryption key is not valid Base64'
        end

        Registry.setup!
        raise EncryptionError, 'No encryption providers available' unless Registry.default_provider
      end

      private

      def encryption_keys
        Familia.config.encryption_keys || {}
      end

      def current_key_version
        Familia.config.current_key_version
      end
    end
  end
end
