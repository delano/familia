# lib/familia/verifiable_identifier.rb

require 'openssl'
require_relative 'secure_identifier'

module Familia
  # Creates and verifies identifiers that contain an embedded HMAC signature,
  # allowing for stateless verification of an identifier's authenticity.
  module VerifiableIdentifier
    # By extending SecureIdentifier, we gain access to its instance methods
    # (like generate_id) as class methods on this module.
    extend Familia::SecureIdentifier

    # The secret key for HMAC generation, loaded from an environment variable.
    #
    # This key is the root of trust for verifying identifier authenticity. It must be
    # a long, random, and cryptographically strong string.
    #
    # @!attribute [r] SECRET_KEY
    #   @return [String] The secret key.
    #
    # @note Security Considerations:
    #   - **Secrecy:** This key MUST be kept secret and secure, just like a database
    #     password or API key. Do not commit it to version control.
    #   - **Consistency:** All running instances of your application must use the
    #     exact same key, otherwise verification will fail across different servers.
    #   - **Rotation:** If this key is ever compromised, it must be rotated. Be
    #     aware that rotating the key will invalidate all previously generated
    #     verifiable identifiers.
    #
    # @example Generating and Setting the Key
    #     1. Generate a new secure key in your terminal:
    #        $ openssl rand -hex 32
    #        > cafef00dcafef00dcafef00dcafef00dcafef00dcafef00d
    #
    #     2. Set it as an environment variable in your production environment:
    #        export VERIFIABLE_ID_HMAC_SECRET="cafef00dcafef00dcafef00dcafef00dcafef00dcafef00d"
    #
    SECRET_KEY = ENV.fetch('VERIFIABLE_ID_HMAC_SECRET', 'cafef00dcafef00dcafef00dcafef00dcafef00dcafef00d')

    # The length of the random part of the ID in hex characters (256 bits).
    RANDOM_HEX_LENGTH = 64
    # The length of the HMAC tag in hex characters (64 bits).
    # 64 bits is strong enough to prevent forgery (1 in 18 quintillion chance).
    TAG_HEX_LENGTH = 16

    # Generates a verifiable, base-36 encoded identifier.
    #
    # The final identifier contains a 256-bit random component and a 64-bit
    # authentication tag.
    #
    # @param base [Integer] The base for encoding the output string.
    # @return [String] A verifiable, signed identifier.
    def self.generate_verifiable_id(base_or_scope = nil, scope: nil, base: 36)
      # Handle backward compatibility with positional base argument
      if base_or_scope.is_a?(Integer)
        base = base_or_scope
        # scope remains as passed in keyword argument
      elsif base_or_scope.is_a?(String) || base_or_scope.nil?
        scope = base_or_scope if scope.nil?
        # base remains as passed in keyword argument or default
      end

      # Re-use generate_id from the SecureIdentifier module.
      random_hex = generate_id(16)
      tag_hex = generate_tag(random_hex, scope: scope)

      combined_hex = random_hex + tag_hex

      # Re-use the min_length_for_bits helper from the SecureIdentifier module.
      total_bits = (RANDOM_HEX_LENGTH + TAG_HEX_LENGTH) * 4
      target_length = Familia::SecureIdentifier.min_length_for_bits(total_bits, base)

      combined_hex.to_i(16).to_s(base).rjust(target_length, '0')
    end

    # Verifies the authenticity of a given identifier using a timing-safe comparison.
    #
    # @param verifiable_id [String] The identifier string to check.
    # @param base [Integer] The base of the input string.
    # @return [Boolean] True if the identifier is authentic, false otherwise.
    def self.verified_identifier?(verifiable_id, base_or_scope = nil, scope: nil, base: 36)
      # Handle backward compatibility with positional base argument
      if base_or_scope.is_a?(Integer)
        base = base_or_scope
        # scope remains as passed in keyword argument
      elsif base_or_scope.is_a?(String) || base_or_scope.nil?
        scope = base_or_scope if scope.nil?
        # base remains as passed in keyword argument or default
      end

      return false unless plausible_identifier?(verifiable_id, base)

      expected_hex_length = (RANDOM_HEX_LENGTH + TAG_HEX_LENGTH)
      combined_hex = verifiable_id.to_i(base).to_s(16).rjust(expected_hex_length, '0')

      random_part = combined_hex[0...RANDOM_HEX_LENGTH]
      tag_part = combined_hex[RANDOM_HEX_LENGTH..]

      expected_tag = generate_tag(random_part, scope: scope)
      OpenSSL.secure_compare(expected_tag, tag_part)
    end

    # Checks if an identifier is plausible (correct format and length) without
    # performing cryptographic verification.
    #
    # This can be used as a fast pre-flight check to reject obviously
    # malformed identifiers.
    #
    # @param identifier_str [String] The identifier string to check.
    # @param base [Integer] The base of the input string.
    # @return [Boolean] True if the identifier has a valid format, false otherwise.
    def self.plausible_identifier?(identifier_str, base = 36)
      return false unless identifier_str.is_a?(::String)

      # 1. Check length
      total_bits = (RANDOM_HEX_LENGTH + TAG_HEX_LENGTH) * 4
      expected_length = Familia::SecureIdentifier.min_length_for_bits(total_bits, base)
      return false unless identifier_str.length == expected_length

      # 2. Check character set
      # The most efficient way to check for invalid characters is to attempt
      # conversion and rescue the error.
      Integer(identifier_str, base)
      true
    rescue ArgumentError
      false
    end

    class << self
      private

      # Generates the HMAC tag for a given message.
      # @private
      def generate_tag(message, scope: nil)
        # Include scope in HMAC calculation for domain separation if provided.
        # The scope parameter enables creating cryptographically isolated identifier
        # namespaces (e.g., per-domain, per-tenant, per-application) while maintaining
        # all security properties of the base system.
        #
        # Security considerations for scope values:
        # - Any string content is cryptographically safe (HMAC handles arbitrary input)
        # - No length restrictions (short scopes like "a" or long scopes work equally well)
        # - UTF-8 encoding is handled consistently
        # - Empty string "" vs nil produce different identifiers (intentional for security)
        # - Different scope values guarantee different identifier spaces
        #
        # Examples of scope usage:
        # - Customer isolation: scope: "tenant:#{tenant_id}"
        # - Environment separation: scope: "production" vs scope: "staging"
        # - Domain scoping: scope: "example.com"
        # - Application scoping: scope: "#{app_name}:#{version}"
        hmac_input = scope ? "#{message}:scope:#{scope}" : message

        digest = OpenSSL::Digest.new('sha256')
        hmac = OpenSSL::HMAC.hexdigest(digest, SECRET_KEY, hmac_input)
        # Truncate to the desired length for the tag.
        hmac[0...TAG_HEX_LENGTH]
      end
    end
  end
end
