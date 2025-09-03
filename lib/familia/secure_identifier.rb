# lib/familia/secure_identifier.rb

require 'securerandom'

# Provides a suite of tools for generating and manipulating cryptographically
# secure identifiers in various formats and lengths.
module Familia
  module SecureIdentifier
    # Generates a 256-bit cryptographically secure hexadecimal identifier.
    #
    # @return [String] A 64-character hex string representing 256 bits of entropy.
    # @security Provides ~10^77 possible values, far exceeding UUIDv4's 128 bits.
    def generate_hex_id
      SecureRandom.hex(32)
    end

    # Generates a 64-bit cryptographically secure hexadecimal trace identifier.
    #
    # @return [String] A 16-character hex string representing 64 bits of entropy.
    # @note 64 bits provides ~18 quintillion values, sufficient for request tracing.
    def generate_hex_trace_id
      SecureRandom.hex(8)
    end

    # Generates a cryptographically secure identifier, encoded in the specified base.
    # By default, this creates a compact, URL-safe base-36 string.
    #
    # @param base [Integer] The base for encoding the output string (2-36, default: 36).
    # @return [String] A secure identifier.
    def generate_id(base = 36)
      target_length = SecureIdentifier.min_length_for_bits(256, base)
      generate_hex_id.to_i(16).to_s(base).rjust(target_length, '0')
    end

    # Generates a short, secure trace identifier, encoded in the specified base.
    # Suitable for tracing, logging, and other ephemeral use cases.
    #
    # @param base [Integer] The base for encoding the output string (2-36, default: 36).
    # @return [String] A secure short identifier.
    def generate_trace_id(base = 36)
      target_length = SecureIdentifier.min_length_for_bits(64, base)
      generate_hex_trace_id.to_i(16).to_s(base).rjust(target_length, '0')
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

      unless hex_id.match?(/\A[0-9a-fA-F]+\z/)
        raise ArgumentError, "Invalid hexadecimal string: #{hex_id}"
      end

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
