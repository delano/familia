# lib/familia/encryption/registry.rb

module Familia
  module Encryption
    # Registry pattern for managing encryption providers
    class Registry
      class << self
        def providers
          @providers ||= {}
        end

        def register(provider_class)
          return unless provider_class.available?

          providers[provider_class::ALGORITHM] = provider_class
        end

        def get(algorithm)
          provider_class = providers[algorithm]
          raise EncryptionError, "Unsupported algorithm: #{algorithm}" unless provider_class

          provider_class.new
        end

        def default_provider
          # Select provider with highest priority
          @default_provider ||= begin
            available = providers.values.select(&:available?)
            available.max_by(&:priority)&.new
          end
        end

        def reset_default_provider!
          @default_provider = nil
        end

        def available_algorithms
          providers.keys
        end

        # Auto-register known providers
        def setup!
          register(Providers::XChaCha20Poly1305Provider)
          register(Providers::AESGCMProvider)
          # Future: register(Providers::ChaCha20Poly1305Provider)
        end
      end
    end
  end
end
