# rubocop:disable all

require 'securerandom'

module Familia

  module Utils

    # Generates a 256-bit cryptographically secure hexadecimal identifier.
    #
    # @return [String] A 64-character hex string representing 256 bits of entropy.
    # @security Provides ~10^77 possible values, far exceeding UUID4's 128 bits.
    def generate_hex_id
      SecureRandom.hex(32)
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
      generate_hex_id.to_i(16).to_s(base)
    end

    # Generates a 64-bit cryptographically secure hexadecimal trace identifier.
    #
    # @return [String] A 16-character hex string representing 64 bits of entropy.
    # @note 64 bits provides ~18 quintillion values, sufficient for request tracing.
    def generate_hex_trace_id
      SecureRandom.hex(8)
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
      generate_hex_trace_id.to_i(16).to_s(base)
    end

    # Truncates a 256-bit hexadecimal ID to 128 bits and encodes it in a given base.
    # This function takes the most significant bits from the hex string to maintain
    # randomness while creating a shorter, deterministic identifier.
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
      truncated = hex_id.to_i(16) >> (256 - 128)  # Always 128 bits
      truncated.to_s(base)
    end

    # Truncates a 256-bit hexadecimal ID to 64 bits and encodes it in a given base.
    #
    # @param hex_id [String] A 64-character hexadecimal string (representing 256 bits).
    # @param base [Integer] The base for encoding the output string (2-36, default: 36).
    # @return [String] A 64-bit identifier, encoded in the specified base.
    def shorten_to_trace_id(hex_id, base: 36)
      truncated = hex_id.to_i(16) >> (256 - 64)   # Always 64 bits
      truncated.to_s(base)
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
