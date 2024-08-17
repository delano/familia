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

    def now(name = Time.now)
      name.utc.to_f
    end

    # A quantized timestamp
    # e.g. 12:32 -> 12:30
    #
    def qnow(quantum = 10.minutes, now = Familia.now)
      rounded = now - (now % quantum)
      Time.at(rounded).utc.to_i
    end

    def qstamp(quantum = nil, pattern = nil, now = Familia.now)
      quantum ||= ttl || 10.minutes
      pattern ||= '%H%M'
      rounded = now - (now % quantum)
      Time.at(rounded).utc.strftime(pattern)
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
        Familia.trace :TOREDIS_DISTINGUISHER, redis, "string", caller(1..1) if Familia.debug?
        # Symbols and numerics are naturally serializable to strings
        # so it's a relatively low risk operation.
        value_to_distinguish.to_s

      when ::TrueClass, ::FalseClass, ::NilClass
        Familia.trace :TOREDIS_DISTINGUISHER, redis, "true/false/nil", caller(1..1) if Familia.debug?
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
        Familia.trace :TOREDIS_DISTINGUISHER, redis, "base", caller(1..1) if Familia.debug?
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
