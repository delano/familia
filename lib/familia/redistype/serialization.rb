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

        elsif dump_method && value_to_distinguish.respond_to?(dump_method)
          Familia.trace :TOREDIS_DISTINGUISHER, redis, "#{value_to_distinguish.class}##{dump_method}", caller(1..1) if Familia.debug?
          value_to_distinguish.send(dump_method)

        else
          Familia.trace :TOREDIS_DISTINGUISHER, redis, "else2 #{strict_values}", caller(1..1) if Familia.debug?
          raise Familia::HighRiskFactor, value_to_distinguish if strict_values
          nil
        end
      end
    end
    protected :distinguisher

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
        ret = distinguisher(opts[:class], strict_values)
        Familia.ld "  from opts[class] <#{opts[:class]}>: #{ret||'<nil>'}"
      end

      if ret.nil?
        # Enforce strict values when no class option is specified
        ret = distinguisher(val, true)
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

    def update_expiration(ttl = nil)
      ttl ||= opts[:ttl]
      return if ttl.to_i.zero? # nil will be zero

      Familia.ld "#{rediskey} to #{ttl}"
      expire ttl.to_i
    end

  end

end
