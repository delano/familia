# rubocop:disable all

require 'securerandom'

module Familia
  DIGEST_CLASS = Digest::SHA256

  module Utils

    def debug?
      @debug == true
    end

    def generate_id
      input = SecureRandom.hex(32)  # 16=128 bits, 32=256 bits
      Digest::SHA256.hexdigest(input).to_i(16).to_s(36) # base-36 encoding
    end

    def join(*val)
      val.compact.join(Familia.delim)
    end

    def split(val)
      val.split(Familia.delim)
    end

    def rediskey(*val)
      join(*val)
    end

    def redisuri(uri)
      generic_uri = URI.parse(uri.to_s)

      # Create a new URI::Redis object
      redis_uri = URI::Redis.build(
        scheme: generic_uri.scheme,
        userinfo: generic_uri.userinfo,
        host: generic_uri.host,
        port: generic_uri.port,
        path: generic_uri.path,
        query: generic_uri.query,
        fragment: generic_uri.fragment
      )

      redis_uri
    end

    def Familia.now(name = Time.now)
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

    def generate_sha_hash(*elements)
      concatenated_string = Familia.join(*elements)
      DIGEST_CLASS.hexdigest(concatenated_string)
    end

    # This method determines the appropriate value to return based on the class of the input argument.
    # It uses a case statement to handle different classes:
    # - For Symbol, String, Integer, and Float classes, it traces the operation and converts the value to a string.
    # - For Familia::Horreum class, it traces the operation and returns the identifier of the value.
    # - For TrueClass, FalseClass, and NilClass, it traces the operation and converts the value to a string ("true", "false", or "").
    # - For any other class, it traces the operation and returns nil.
    #
    # Alternative names for `value_to_distinguish` could be `input_value`, `value`, or `object`.
    def distinguisher(value_to_distinguish, strict_values = true)
      case value_to_distinguish
      when ::Symbol, ::String, ::Integer, ::Float
        #Familia.trace :TOREDIS_DISTINGUISHER, redis, "string", caller(1..1) if Familia.debug?
        # Symbols and numerics are naturally serializable to strings
        # so it's a relatively low risk operation.
        value_to_distinguish.to_s

      when ::TrueClass, ::FalseClass, ::NilClass
        #Familia.trace :TOREDIS_DISTINGUISHER, redis, "true/false/nil", caller(1..1) if Familia.debug?
        # TrueClass, FalseClass, and NilClass are high risk because we can't
        # reliably determine the original type of the value from the serialized
        # string. This can lead to unexpected behavior when deserializing. For
        # example, if a TrueClass value is serialized as "true" and then later
        # deserialized as a String, it can cause errors in the application. Worse
        # still, if a NilClass value is serialized as an empty string we lose the
        # ability to distinguish between a nil value and an empty string when
        #
        raise Familia::HighRiskFactor, value_to_distinguish if strict_values
        value_to_distinguish.to_s #=> "true", "false", ""

      when Familia::Base, Class
        #Familia.trace :TOREDIS_DISTINGUISHER, redis, "base", caller(1..1) if Familia.debug?
        if value_to_distinguish.is_a?(Class)
          value_to_distinguish.name
        else
          value_to_distinguish.identifier
        end

      else
        #Familia.trace :TOREDIS_DISTINGUISHER, redis, "else1 #{strict_values}", caller(1..1) if Familia.debug?

        if value_to_distinguish.class.ancestors.member?(Familia::Base)
          #Familia.trace :TOREDIS_DISTINGUISHER, redis, "isabase", caller(1..1) if Familia.debug?
          value_to_distinguish.identifier

        else
          #Familia.trace :TOREDIS_DISTINGUISHER, redis, "else2 #{strict_values}", caller(1..1) if Familia.debug?
          raise Familia::HighRiskFactor, value_to_distinguish if strict_values
          nil
        end
      end
    end

  end
end
