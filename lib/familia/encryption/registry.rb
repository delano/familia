# lib/familia/encryption/registry.rb
#
# frozen_string_literal: true

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
          return provider_class.new if provider_class

          # Not registered. `register` only stores providers whose runtime
          # dependency is present (available? == true), so distinguish a
          # genuinely unknown algorithm from a known one whose provider isn't
          # installed on this node. The latter is the common misstep when
          # pinning `encrypted_field ..., algorithm:` ahead of a fleet rollout
          # (e.g. pinning xchacha20poly1305 before rbnacl/libsodium is
          # deployed), so point at the real fix instead of implying a typo.
          known = known_providers.find { |klass| algorithm == klass::ALGORITHM }
          if known
            # Each provider declares its own dependency (via .dependency_hint),
            # so this generic path stays accurate as providers are added without
            # naming any one library here.
            dependency = known.dependency_hint
            requirement = dependency ? " (requires #{dependency})" : ''
            raise EncryptionError,
                  "Algorithm #{algorithm.inspect} is known but its provider " \
                  "(#{known.name}) is not available on this node -- its " \
                  "runtime dependency is missing#{requirement}. Install the " \
                  'dependency, or pin to an available algorithm: ' \
                  "#{available_algorithms.inspect}."
          end

          raise EncryptionError, "Unsupported algorithm: #{algorithm}"
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

        # Every provider class Familia knows how to register, regardless of
        # whether its runtime dependency is available on this node. `providers`
        # holds only the subset that passed `available?`; this is the full set,
        # and the single source of truth shared by `setup!` (which registers
        # the available ones) and `get` (which uses it to tell an unknown
        # algorithm apart from a known-but-unavailable one).
        def known_providers
          [
            Providers::XChaCha20Poly1305Provider,
            Providers::AESGCMProvider,
            # Future: Providers::ChaCha20Poly1305Provider
          ]
        end

        # Auto-register known providers
        def setup!
          known_providers.each { |provider_class| register(provider_class) }
        end
      end
    end
  end
end
