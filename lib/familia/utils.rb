# rubocop:disable all

require 'securerandom'

module Familia

  module Utils

    # Checks if debug mode is enabled
    #
    # e.g. Familia.debug = true
    #
    # @return [Boolean] true if debug mode is on, false otherwise
    def debug?
      @debug == true
    end

    # Generates a unique ID using SHA256 and base-36 encoding
    # @param length [Integer] length of the random input in bytes (default: 32)
    # @param encoding [Integer] base encoding for the output (default: 36)
    # @return [String] a unique identifier
    #
    # @example Generate a default ID
    #   Familia.generate_id
    #   # => "kuk79w6uxg81tk0kn5hsl6pr7ic16e9p6evjifzozkda9el6z"
    #
    # @example Generate a shorter ID with 16 bytes input
    #   Familia.generate_id(length: 16)
    #   # => "z6gqw1b7ftzpvapydkt0iah0h0bev5hkhrs4mkf1gq4nq5csa"
    #
    # @example Generate an ID with hexadecimal encoding
    #   Familia.generate_id(encoding: 16)
    #   # => "d06a2a70cba543cd2bbd352c925bc30b0a9029ca79e72d6556f8d6d8603d5716"
    #
    # @example Generate a shorter ID with custom encoding
    #   Familia.generate_id(length: 8, encoding: 32)
    #   # => "193tosc85k3u513do2mtmibchpd2ruh5l3nsp6dnl0ov1i91h7m7"
    #
    def generate_id(length: 32, encoding: 36)
      raise ArgumentError, "Encoding must be between 2 and 36" unless (1..36).include?(encoding)

      input = SecureRandom.hex(length)
      Digest::SHA256.hexdigest(input).to_i(16).to_s(encoding)
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
