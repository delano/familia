# rubocop:disable all

class Familia::RedisType

  module Serialization

    # Serializes an individual value for storage in Redis.
    #
    # This method prepares a value for storage in Redis by converting it to a string representation.
    # If a class option is specified, it uses that class's serialization method.
    # Otherwise, it relies on the value's own `to_s` method for serialization.
    #
    # @param val [Object] The value to be serialized.
    # @param strict_values [Boolean] Whether to enforce strict value serialization (default: true). Only applies when no class option is specified because the class option is assumed to handle its own serialization.
    # @return [String] The serialized representation of the value.
    #
    # @note When no class option is specified, this method attempts to serialize the value directly.
    #       If the serialization fails, it falls back to the value's own string representation.
    #
    # @example With a class option
    #   to_redis(User.new(name: "John"), strict_values: false) #=> '{"name":"John"}'
    #   to_redis(nil, strict_values: false) #=> "" (empty string)
    #   to_redis(true, strict_values: false) #=> "true"
    #
    # @example Without a class option and strict values
    #   to_redis(123) #=> "123" (which becomes "123" in Redis)
    #   to_redis("hello") #=> "hello"
    #   to_redis(nil) # raises an exception
    #   to_redis(true) # raises an exception
    #
    # @raise [Familia::HighRiskFactor]
    #
    def to_redis(val, strict_values = true)
      ret = nil

      Familia.trace :TOREDIS, redis, "#{val}<#{val.class}|#{opts[:class]}>", caller(1..1) if Familia.debug?

      if opts[:class]
        ret = Familia.distinguisher(opts[:class], strict_values)
        Familia.ld "  from opts[class] <#{opts[:class]}>: #{ret||'<nil>'}"
      end

      if ret.nil?
        # Enforce strict values when no class option is specified
        ret = Familia.distinguisher(val, true)
        Familia.ld "  from value #{val}<#{val.class}>: #{ret}<#{ret.class}>"
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
  end

end
