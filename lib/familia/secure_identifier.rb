# lib/familia/secure_identifier.rb
#
# frozen_string_literal: true

require 'securerandom'

# Provides a suite of tools for generating and manipulating cryptographically
# secure identifiers in various formats and lengths.
module Familia
  # Cryptographically secure random identifiers.
  #
  # Strength tiers
  # --------------
  # 256-bit : cryptographic secrets, session tokens, API keys
  # 128-bit : business/user IDs, product SKUs, non-secret resources
  #  64-bit : request tracing, log correlation, ephemeral tags
  #
  # All methods use `SecureRandom`; collisions are probabilistic and
  # scale with the number of generated values, not time.
  #
  module SecureIdentifier
    # 256-bit identifier – the "full-strength" version.
    #
    # Safe for:
    #   * cryptographic secrets, session tokens, API keys
    #   * any identifier that must resist brute-force or intentional guessing
    #
    # @param base [Integer] 2–36, defaults to 36 for URL-safe chars
    # @return [String] identifier in specified base, zero-padded to minimum length for 256 bits
    def generate_id(base = 36)
      _generate_secure_id(bits: 256, base: base)
    end

    # 128-bit identifier – the "lite" version.
    #
    # Safe for:
    #   * ~ 10¹⁵ generated values (collision risk < 10⁻⁹)
    #   * business/user IDs, product SKUs, non-secret resources
    #
    # NOT safe for:
    #   * security tokens that must resist intentional guessing
    #
    # @param base [Integer] 2–36, defaults to 36 for URL-safe chars
    # @return [String] identifier in specified base, zero-padded to minimum length for 128 bits
    def generate_lite_id(base = 36)
      _generate_secure_id(bits: 128, base: base)
    end

    # 64-bit identifier – the "trace" version.
    #
    # Safe for:
    #   * request tracing, log correlation, ephemeral tags
    #   * up to ~ 10⁹ values (collision risk < 10⁻⁶)
    #
    # NOT safe for:
    #   * long-lived identifiers or security contexts
    #
    # @param base [Integer] 2–36, defaults to 36 for URL-safe chars
    # @return [String] identifier in specified base, zero-padded to minimum length for 64 bits
    def generate_trace_id(base = 36)
      _generate_secure_id(bits: 64, base: base)
    end

    # Creates a deterministic 64-bit trace identifier from a longer hex ID.
    #
    # This is a convenience method for `truncate_hex(hex_id, bits: 64)`.
    # Useful for creating short, consistent IDs for logging and tracing.
    #
    # @param (see #truncate_hex)
    # @return (see #truncate_hex)
    def shorten_to_trace_id(hex_id, base: 36)
      truncate_hex(hex_id, bits: 64, base: base)
    end

    # Deterministically truncates a hexadecimal ID to a specified bit length.
    #
    # This function preserves the most significant bits of the input `hex_id` to
    # create a shorter, yet still random-looking, identifier.
    #
    # @param hex_id [String] The input hexadecimal string.
    # @param bits [Integer] The desired output bit length (e.g., 128, 64). Defaults to 128.
    # @param base [Integer] The numeric base for the output string (2-36). Defaults to 36.
    # @return [String] A new, shorter identifier in the specified base.
    # @raise [ArgumentError] if `hex_id` is not a valid hex string, or if `input_bits`
    #   is less than the desired output `bits`.
    def truncate_hex(hex_id, bits: 128, base: 36)
      target_length = SecureIdentifier.min_length_for_bits(bits, base)
      input_bits = hex_id.length * 4

      raise ArgumentError, "Invalid hexadecimal string: #{hex_id}" unless hex_id.match?(/\A[0-9a-fA-F]+\z/)

      if input_bits < bits
        raise ArgumentError, "Input bits (#{input_bits}) cannot be less than desired output bits (#{bits})."
      end

      # Truncate by right-shifting to keep the most significant bits
      truncated_int = hex_id.to_i(16) >> (input_bits - bits)
      truncated_int.to_s(base).rjust(target_length, '0')
    end

    # Calculates the minimum string length required to represent a given number of
    # bits in a specific numeric base.
    #
    private

    # Generates a secure identifier with specified bit length and base.
    #
    # @private
    #
    # @param bits [Integer] The number of bits of entropy (64, 128, or 256).
    # @param base [Integer] The numeric base (2-36).
    # @return [String] The generated identifier.
    def _generate_secure_id(bits:, base:)
      hex_id = SecureRandom.hex(bits / 8)
      return hex_id if base == 16

      len = SecureIdentifier.min_length_for_bits(bits, base)
      hex_id.to_i(16).to_s(base).rjust(len, '0')
    end

    # @private
    #
    # @param bits [Integer] The number of bits of entropy.
    # @param base [Integer] The numeric base (2-36).
    # @return [Integer] The minimum string length required.
    def self.min_length_for_bits(bits, base)
      # Fast lookup for hex (base 16) - our most common case
      hex_lengths = {
        256 => 64,  # SHA-256 equivalent entropy
        128 => 32,  # UUID equivalent entropy
        64  => 16,  # Compact ID
      }.freeze
      return hex_lengths[bits] if base == 16 && hex_lengths.key?(bits)

      @min_length_for_bits_cache ||= {}
      @min_length_for_bits_cache[[bits, base]] ||= (bits * Math.log(2) / Math.log(base)).ceil
    end
  end
end
