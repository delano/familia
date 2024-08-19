# rubocop:disable all

class Familia::RedisType

  module Serialization

    # Serializes a value for storage in Redis.
    #
    # @param val [Object] The value to be serialized.
    # @param strict_values [Boolean] Whether to enforce strict value
    #   serialization (default: true).
    # @return [String, nil] The serialized representation of the value, or nil
    #   if serialization fails.
    #
    # @note When a class option is specified, it uses that class's
    #   serialization method. Otherwise, it relies on Familia.distinguisher for
    #   serialization.
    #
    # @example With a class option
    #   to_redis(User.new(name: "Cloe"), strict_values: false) #=> '{"name":"Cloe"}'
    #
    # @example Without a class option
    #   to_redis(123) #=> "123"
    #   to_redis("hello") #=> "hello"
    #
    # @raise [Familia::HighRiskFactor] If serialization fails under strict
    #   mode.
    #
    def to_redis(val, strict_values = true)
      prepared = nil

      Familia.trace :TOREDIS, redis, "#{val}<#{val.class}|#{opts[:class]}>", caller(1..1) if Familia.debug?

      if opts[:class]
        prepared = Familia.distinguisher(opts[:class], strict_values)
        Familia.ld "  from opts[class] <#{opts[:class]}>: #{prepared||'<nil>'}"
      end

      if prepared.nil?
        # Enforce strict values when no class option is specified
        prepared = Familia.distinguisher(val, true)
        Familia.ld "  from <#{val.class}> => <#{prepared.class}>"
      end

      Familia.trace :TOREDIS, redis, "#{val}<#{val.class}|#{opts[:class]}> => #{prepared}<#{prepared.class}>", caller(1..1) if Familia.debug?

      Familia.warn "[#{self.class}\#to_redis] nil returned for #{opts[:class]}\##{name}" if prepared.nil?
      prepared
    end

    # Deserializes multiple values from Redis, removing nil values.
    #
    # @param values [Array<String>] The values to deserialize.
    # @return [Array<Object>] Deserialized objects, with nil values removed.
    #
    # @see #multi_from_redis_with_nil
    #
    def multi_from_redis(*values)
      # Avoid using compact! here. Using compact! as the last expression in the
      # method can unintentionally return nil if no changes are made, which is
      # not desirable. Instead, use compact to ensure the method returns the
      # expected value.
      multi_from_redis_with_nil(*values).compact
    end

    # Deserializes multiple values from Redis, preserving nil values.
    #
    # @param values [Array<String>] The values to deserialize.
    # @return [Array<Object, nil>] Deserialized objects, including nil values.
    #
    # @raise [Familia::Problem] If the specified class doesn't respond to the
    #   load method.
    #
    # @note This method attempts to deserialize each value using the specified
    #   class's load method. If deserialization fails for a value, it's
    #   replaced with nil.
    #
    # NOTE: `multi` in this method name refers to multiple values from
    # redis and not the Redis server MULTI command.
    #
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

    # Deserializes a single value from Redis.
    #
    # @param val [String, nil] The value to deserialize.
    # @return [Object, nil] The deserialized object, the default value if
    #   val is nil, or nil if deserialization fails.
    #
    # @note If no class option is specified, the original value is
    #   returned unchanged.
    #
    # NOTE: Currently only the RedisType class uses this method. Horreum
    # fields are a newer addition and don't support the full range of
    # deserialization options that RedisType supports. It uses to_redis
    # for serialization since everything becomes a string in Redis.
    #
    def from_redis(val)
      return @opts[:default] if val.nil?
      return val unless @opts[:class]

      ret = multi_from_redis val
      ret&.first # return the object or nil
    end
  end

end
