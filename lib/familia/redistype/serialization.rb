# rubocop:disable all

class Familia::RedisType

  module Serialization

    # This method determines the appropriate value to return based on the class of the input argument.
    # It uses a case statement to handle different classes:
    # - For Symbol, String, Integer, and Float classes, it traces the operation and converts the value to a string.
    # - For Familia::Horreum class, it traces the operation and returns the identifier of the value.
    # - For TrueClass, FalseClass, and NilClass, it traces the operation and converts the value to a string ("true", "false", or "").
    # - For any other class, it traces the operation and returns nil.
    #
    # Alternative names for `value_to_discriminate` could be `input_value`, `value`, or `object`.
    def discriminator(value_to_discriminate, strict_values = true)
      case value_to_discriminate
      when ::Symbol, ::String, ::Integer, ::Float
        Familia.trace :TOREDIS_DISCRIMINATOR, redis, "string", caller(1..1) if Familia.debug?
        # Symbols and numerics are naturally serializable to strings
        # so it's a relatively low risk operation.
        value_to_discriminate.to_s

      when ::TrueClass, ::FalseClass, ::NilClass
        Familia.trace :TOREDIS_DISCRIMINATOR, redis, "true/false/nil", caller(1..1) if Familia.debug?
        # TrueClass, FalseClass, and NilClass are high risk because we can't
        # reliably determine the original type of the value from the serialized
        # string. This can lead to unexpected behavior when deserializing. For
        # example, if a TrueClass value is serialized as "true" and then later
        # deserialized as a String, it can cause errors in the application. Worse
        # still, if a NilClass value is serialized as an empty string we lose the
        # ability to distinguish between a nil value and an empty string when
        #
        raise Familia::HighRiskFactor, value_to_discriminate if strict_values
        value_to_discriminate.to_s #=> "true", "false", ""

      else
        if value_to_discriminate.is_a?(Familia::Horreum)
          Familia.trace :TOREDIS_DISCRIMINATOR, redis, "horreum", caller(1..1) if Familia.debug?
          value_to_discriminate.identifier

        elsif dump_method && value_to_discriminate.respond_to?(dump_method)
          Familia.trace :TOREDIS_DISCRIMINATOR, redis, "#{value_to_discriminate.class}##{dump_method}", caller(1..1) if Familia.debug?
          value_to_discriminate.send(dump_method)

        else
          Familia.trace :TOREDIS_DISCRIMINATOR, redis, "else", caller(1..1) if Familia.debug?
          raise Familia::HighRiskFactor, value_to_discriminate if strict_values
          nil
        end
      end
    end
    protected :discriminator

    # Serializes an individual value for storage in Redis.
    #
    # This method prepares a value for storage in Redis by converting it to a string representation.
    # If a class option is specified, it uses that class's serialization method (default: to_json).
    # Otherwise, it relies on the value's own `to_s` method for serialization.
    #
    # @param val [Object] The value to be serialized.
    # @return [String] The serialized representation of the value.
    #
    # @note When no class option is specified, this method directly returns the input value,
    #       which implicitly calls `to_s` when Redis stores it. This behavior relies on
    #       the object's own string representation.
    #
    # @example With a class option
    #   to_redis(User.new(name: "John")) #=> '{"name":"John"}'
    #
    # @example Without a class option
    #   to_redis(123) #=> "123" (which becomes "123" in Redis)
    #   to_redis("hello") #=> "hello"
    #
    def to_redis(val)
      #return val.to_s unless opts[:class]
      ret = nil

      Familia.trace :TOREDIS, redis, "#{val}<#{val.class}|#{opts[:class]}>", caller(1..1) if Familia.debug?

      if opts[:class]
        ret = discriminator(opts[:class], strict_values: false)
        Familia.ld "  from opts[class] <#{opts[:class]}>: #{ret||'<nil>'}"
      end

      if ret.nil?
        ret = discriminator(val, strict_values: true)
        Familia.ld "  from value #{val}: #{ret}"
      end

      Familia.trace :TOREDIS, redis, "#{val}<#{val.class}|#{opts[:class]}> => #{ret}<#{ret.class}>", caller(1..1) if Familia.debug?

      Familia.warn "[#{self.class}\#to_redis] nil returned for #{opts[:class]}\##{name}" if ret.nil?
      ret
    end

    def multi_from_redis(*values)
      # Avoid using compact! here. Using compact! as the last expression in the method
      # can unintentionally return nil if no changes are made, which is not desirable.
      # Instead, use compact to ensure the method returns the expected value.
      multi_from_redis_with_nil(*values).compact
    end

    # NOTE: `multi` in this method name refers to multiple values from
    # redis and not the Redis server MULTI command.
    def multi_from_redis_with_nil(*values)
      Familia.ld "multi_from_redis: (#{@opts}) #{values}"
      return [] if values.empty?
      return values.flatten unless @opts[:class]

      unless @opts[:class].respond_to?(load_method)
        raise Familia::Problem, "No such method: #{@opts[:class]}##{load_method}"
      end

      values.collect! do |obj|
        next if obj.nil?

        val = @opts[:class].send load_method, obj
        if val.nil?
          Familia.ld "[#{self.class}\#multi_from_redis] nil returned for #{@opts[:class]}\##{name}"
        end

        val
      rescue StandardError => e
        Familia.info val
        Familia.info "Parse error for #{rediskey} (#{load_method}): #{e.message}"
        Familia.info e.backtrace
        nil
      end

      values
    end

    def from_redis(val)
      return @opts[:default] if val.nil?
      return val unless @opts[:class]

      ret = multi_from_redis val
      ret&.first # return the object or nil
    end

    def update_expiration(ttl = nil)
      ttl ||= opts[:ttl]
      return if ttl.to_i.zero? # nil will be zero

      Familia.ld "#{rediskey} to #{ttl}"
      expire ttl.to_i
    end

  end

end
