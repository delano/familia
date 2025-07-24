# rubocop:disable all

require 'securerandom'

module Familia

  module Utils

    # Generates a cryptographically secure identifier using SecureRandom.
    # Creates a random hexadecimal string and converts it to base-36 encoding
    # for a compact, URL-safe identifier.
    #
    # @return [String] A secure identifier in base-36 encoding
    #
    # @example Generate a 256-bit ID in base-36
    #   Familia.generate_id # => "25nkfebno45yy36z47ffxef2a7vpg4qk06ylgxzwgpnz4q3os4"
    #
    # @security Uses SecureRandom for cryptographic entropy
    # @see #convert_base_string for base conversion details
    def generate_id
      hexstr = SecureRandom.hex(32)
      convert_base_string(hexstr)
    end

    # Generates a cryptographically secure short identifier by creating
    # a 256-bit random value and then truncating it to 64 bits for a
    # shorter but still secure identifier.
    #
    # @return [String] A secure short identifier in base-36 encoding
    #
    # @example Generate a 64-bit short ID
    #   Utils.generate_short_id # => "k8x2m9n4p7q1"
    #
    # @security Uses SecureRandom for entropy with secure bit truncation
    # @see #shorten_securely for truncation details
    def generate_short_id
      hexstr = SecureRandom.hex(32) # generate with all 256 bits
      shorten_securely(hexstr, bits: 64) # and then shorten
    end

    # Truncates a hexadecimal string to specified bit length and encodes in desired base.
    # Takes the most significant bits from the hex string to maintain randomness
    # distribution while reducing the identifier length for practical use.
    #
    # @param hash [String] A hexadecimal string (64 characters for 256 bits)
    # @param bits [Integer] Number of bits to retain (default: 256, max: 256)
    # @param base [Integer] Base encoding for output string (2-36, default: 36)
    # @return [String] Truncated value encoded in the specified base
    #
    # @example Truncate to 128 bits in base-16
    #   hash = "a1b2c3d4..." # 64-char hexadecimal string
    #   Utils.shorten_securely(hash, bits: 128, base: 16) # => "a1b2c3d4e5f6e7c8"
    #
    # @example Default 256-bit truncation in base-36
    #   Utils.shorten_securely(hash) # => "k8x2m9n4p7q1r5s3t6u0v2w8x1y4z7"
    #
    # @note Higher bit counts provide more security but longer identifiers
    # @note Base-36 encoding uses 0-9 and a-z for compact, URL-safe strings
    # @security Bit truncation preserves cryptographic properties of original value
    def shorten_securely(hash, bits: 256, base: 36)
      # Truncate to desired bit length
      truncated = hash.to_i(16) >> (256 - bits)
      convert_base_string(truncated.to_s, base: base)
    end

    # Converts a string representation of a number from one base to another.
    # This utility method is flexible, allowing conversions between any bases
    # supported by Ruby's `to_i` and `to_s` methods (i.e., 2 to 36).
    #
    # @param value_str [String] The string representation of the number to convert.
    # @param from_base [Integer] The base of the input `value_str` (default: 16).
    # @param base [Integer] The target base for the output string (default: 36).
    # @return [String] The string representation of the number in the `base`.
    # @raise [ArgumentError] If `from_base` or `base` are outside the valid range (2-36).
    def convert_base_string(value_str, from_base: 16, base: 36)
      unless from_base.between?(2, 36) && base.between?(2, 36)
        raise ArgumentError, 'Bases must be between 2 and 36'
      end

      value_str.to_i(from_base).to_s(base)
    end

    # Joins array elements with Familia delimiter
    # @param val [Array] elements to join
    # @return [String] joined string
    def join(*val)
      val.compact.join(Familia.delim)
    end

    # Splits a string using Familia delimiter
    # @param val [String] string to split
    # @return [Array] split elements
    def split(val)
      val.split(Familia.delim)
    end

    # Creates a Redis key from given values
    # @param val [Array] elements to join for the key
    # @return [String] Redis key
    def rediskey(*val)
      join(*val)
    end

    # Gets server ID without DB component for pool identification
    def serverid(uri)
      # Create a copy of URI without DB for server identification
      uri = uri.dup
      uri.db = nil
      uri.serverid
    end

    # Returns current time in UTC as a float
    # @param name [Time] time object (default: current time)
    # @return [Float] time in seconds since epoch
    def now(name = Time.now)
      name.utc.to_f
    end

    # A quantized timestamp
    #
    # @param quantum [Integer] The time quantum in seconds (default: 10 minutes).
    # @param pattern [String, nil] The strftime pattern to format the timestamp.
    # @param time [Integer, Float, Time, nil] A specific time to quantize (default: current time).
    # @return [Integer, String] A unix timestamp or formatted timestamp string.
    #
    # @example
    #   Familia.qstamp  # Returns an integer timestamp rounded to the nearest 10 minutes
    #   Familia.qstamp(1.hour)  # Uses 1 hour quantum
    #   Familia.qstamp(10.minutes, pattern: '%H:%M')  # Returns a formatted string like "12:30"
    #   Familia.qstamp(10.minutes, time: 1302468980)  # Quantizes the given Unix timestamp
    #   Familia.qstamp(10.minutes, time: Time.now)  # Quantizes the given Time object
    #   Familia.qstamp(10.minutes, pattern: '%H:%M', time: 1302468980)  # Formats a specific time
    #
    def qstamp(quantum = 10.minutes, pattern: nil, time: nil)
      time ||= Familia.now
      time = time.to_f if time.is_a?(Time)

      rounded = time - (time % quantum)

      if pattern
        Time.at(rounded).utc.strftime(pattern)
      else
        Time.at(rounded).utc.to_i
      end
    end


    # This method determines the appropriate transformation to apply based on
    # the class of the input argument.
    #
    # @param [Object] value_to_distinguish The value to be processed. Keep in
    #   mind that all data in redis is stored as a string so whatever the type
    #   of the value, it will be converted to a string.
    # @param [Boolean] strict_values Whether to enforce strict value handling.
    #   Defaults to true.
    # @return [String, nil] The processed value as a string or nil for unsupported
    #   classes.
    #
    # The method uses a case statement to handle different classes:
    # - For `Symbol`, `String`, `Integer`, and `Float` classes, it traces the
    #   operation and converts the value to a string.
    # - For `Familia::Horreum` class, it traces the operation and returns the
    #   identifier of the value.
    # - For `TrueClass`, `FalseClass`, and `NilClass`, it traces the operation and
    #   converts the value to a string ("true", "false", or "").
    # - For any other class, it traces the operation and returns nil.
    #
    # Alternative names for `value_to_distinguish` could be `input_value`, `value`,
    # or `object`.
    #
    def distinguisher(value_to_distinguish, strict_values: true)
      case value_to_distinguish
      when ::Symbol, ::String, ::Integer, ::Float
        Familia.trace :TOREDIS_DISTINGUISHER, redis, "string", caller(1..1) if Familia.debug?

        # Symbols and numerics are naturally serializable to strings
        # so it's a relatively low risk operation.
        value_to_distinguish.to_s

      when ::TrueClass, ::FalseClass, ::NilClass
        Familia.trace :TOREDIS_DISTINGUISHER, redis, "true/false/nil", caller(1..1) if Familia.debug?

        # TrueClass, FalseClass, and NilClass are considered high risk because their
        # original types cannot be reliably determined from their serialized string
        # representations. This can lead to unexpected behavior during deserialization.
        # For instance, a TrueClass value serialized as "true" might be deserialized as
        # a String, causing application errors. Even more problematic, a NilClass value
        # serialized as an empty string makes it impossible to distinguish between a
        # nil value and an empty string upon deserialization. Such scenarios can result
        # in subtle, hard-to-diagnose bugs. To mitigate these risks, we raise an
        # exception when encountering these types unless the strict_values option is
        # explicitly set to false.
        #
        raise Familia::HighRiskFactor, value_to_distinguish if strict_values
        value_to_distinguish.to_s #=> "true", "false", ""

      when Familia::Base, Class
        Familia.trace :TOREDIS_DISTINGUISHER, redis, "base", caller(1..1) if Familia.debug?

        # When called with a class we simply transform it to its name. For
        # instances of Familia class, we store the identifier.
        if value_to_distinguish.is_a?(Class)
          value_to_distinguish.name
        else
          value_to_distinguish.identifier
        end

      else
         Familia.trace :TOREDIS_DISTINGUISHER, redis, "else1 #{strict_values}", caller(1..1) if Familia.debug?

        if value_to_distinguish.class.ancestors.member?(Familia::Base)
          Familia.trace :TOREDIS_DISTINGUISHER, redis, "isabase", caller(1..1) if Familia.debug?

          value_to_distinguish.identifier

        else
          Familia.trace :TOREDIS_DISTINGUISHER, redis, "else2 #{strict_values}", caller(1..1) if Familia.debug?
          raise Familia::HighRiskFactor, value_to_distinguish if strict_values
          nil
        end
      end
    end

  end
end
