# lib/familia/secure_identifier.rb

require 'securerandom'

module Familia
  module SecureIdentifier

    # Generates a 256-bit cryptographically secure hexadecimal identifier.
    #
    # @return [String] A 64-character hex string representing 256 bits of entropy.
    # @security Provides ~10^77 possible values, far exceeding UUID4's 128 bits.
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
    #
    # @example Generate a 256-bit ID in base-36 (default)
    #   generate_id # => "25nkfebno45yy36z47ffxef2a7vpg4qk06ylgxzwgpnz4q3os4"
    #
    # @example Generate a 256-bit ID in base-16 (hexadecimal)
    #   generate_id(16) # => "568bdb582bc5042bf435d3f126cf71593981067463709c880c91df1ad9777a34"
    #
    def generate_id(base = 36)
      target_length = SecureIdentifier.min_length_for_bits(256, base)
      generate_hex_id.to_i(16).to_s(base).rjust(target_length, '0')
    end

    # Generates a short, secure trace identifier, encoded in the specified base.
    # Suitable for tracing, logging, and other ephemeral use cases.
    #
    # @param base [Integer] The base for encoding the output string (2-36, default: 36).
    # @return [String] A secure short identifier.
    #
    # @example Generate a 64-bit short ID in base-36 (default)
    #   generate_trace_id # => "lh7uap704unf"
    #
    # @example Generate a 64-bit short ID in base-16 (hexadecimal)
    #   generate_trace_id(16) # => "94cf9f8cfb0eb692"
    #
    def generate_trace_id(base = 36)
      target_length = SecureIdentifier.min_length_for_bits(64, base)
      generate_hex_trace_id.to_i(16).to_s(base).rjust(target_length, '0')
    end

    # Truncates a 256-bit hexadecimal ID to 64 bits and encodes it in a given base.
    # These short, deterministic IDs are useful for secure logging. By inputting the
    # full hexadecimal string, you can generate a consistent short ID that allows
    # tracking an entity through logs without exposing the entity's full identifier..
    #
    # @param hex_id [String] A 64-character hexadecimal string (representing 256 bits).
    # @param base [Integer] The base for encoding the output string (2-36, default: 36).
    # @return [String] A 64-bit identifier, encoded in the specified base.
    def shorten_to_trace_id(hex_id, base: 36)
      target_length = SecureIdentifier.min_length_for_bits(64, base)
      truncated = hex_id.to_i(16) >> (256 - 64) # Always 64 bits
      truncated.to_s(base).rjust(target_length, '0')
    end

    # Truncates a 256-bit hexadecimal ID to 128 bits and encodes it in a given base.
    # This function takes the most significant bits from the hex string to maintain
    # randomness while creating a shorter, deterministic identifier that's safe for
    # outdoor use.
    #
    # @param hex_id [String] A 64-character hexadecimal string (representing 256 bits).
    # @param base [Integer] The base for encoding the output string (2-36, default: 36).
    # @return [String] A 128-bit identifier, encoded in the specified base.
    #
    # @example Create a shorter external ID from a full 256-bit internal ID
    #   hex_id = generate_hex_id
    #   external_id = shorten_to_external_id(hex_id)
    #
    # @note This is useful for creating shorter, public-facing IDs from secure internal ones.
    # @security Truncation preserves the cryptographic properties of the most significant bits.
    def shorten_to_external_id(hex_id, base: 36)
      target_length = SecureIdentifier.min_length_for_bits(128, base)

      # Calculate actual bit length from hex string
      hex_bits = hex_id.length * 4  # 1 hex char = 4 bits

      case hex_bits
      when 256
        # 256-bit input: truncate to 128 bits by taking the most significant bits
        truncated = hex_id.to_i(16) >> (256 - 128)
      when 128
        # 128-bit input (UUID): use as-is
        truncated = hex_id.to_i(16)
      else
        raise ArgumentError, "Unsupported bit length #{hex_bits}. Expected 128 or 256 bits."
      end

      truncated.to_s(base).rjust(target_length, '0')
    end

    # Calculate minimum string length to represent N bits in given base
    #
    # When generating random IDs, we need to know how many characters are required
    # to represent a certain amount of entropy. This ensures consistent ID lengths.
    #
    # Formula: ceil(bits * log(2) / log(base))
    #
    # @example Common usage with SecureRandom
    #   SecureRandom.hex(32)  # 32 bytes = 256 bits = 64 hex chars
    #   SecureRandom.hex(16)  # 16 bytes = 128 bits = 32 hex chars
    #
    # @example Using the method
    #   min_length_for_bits(256, 16)  # => 64 (hex)
    #   min_length_for_bits(256, 36)  # => 50 (base36)
    #   min_length_for_bits(128, 10)  # => 39 (decimal)

    # Fast lookup for hex (base 16) - our most common case
    # Avoids calculation overhead for 99% of ID generation
    HEX_LENGTHS = {
      256 => 64,  # SHA-256 equivalent entropy
      128 => 32,  # UUID equivalent entropy
      64  => 16,  # Compact ID
    }.freeze

    # Get minimum character length needed to encode `bits` of entropy in `base`
    #
    # @param bits [Integer] Number of bits of entropy needed
    # @param base [Integer] Numeric base (2-36)
    # @return [Integer] Minimum string length required
    def self.min_length_for_bits(bits, base)
      return HEX_LENGTHS[bits] if base == 16 && HEX_LENGTHS.key?(bits)

      @length_cache ||= {}
      @length_cache[[bits, base]] ||= (bits * Math.log(2) / Math.log(base)).ceil
    end
  end
end
