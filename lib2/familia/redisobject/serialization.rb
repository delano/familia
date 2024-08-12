# rubocop:disable all

class Familia::RedisObject

  module Serialization

    # Serialization method for individual values
    def to_redis(val)
      return val unless @opts[:class]

      ret = case @opts[:class]
            when ::Symbol, ::String, ::Integer, ::Float, Gibbler::Digest
              val
            when ::NilClass
              ''
            else
              if val.is_a?(::String)
                val

              elsif val.respond_to? dump_method
                val.send dump_method

              else
                raise Familia::Problem, "No such method: #{val.class}.#{dump_method}"
              end
            end

      Familia.ld "[#{self.class}\#to_redis] nil returned for #{@opts[:class]}\##{name}" if ret.nil?
      ret
    end

    def multi_from_redis(*values)
      # Don't use compact! When using compact like this -- as the last
      # expression in the method -- the return value is obviously intentional.
      # Exclamation mark methods have return values too, usually nil. We don't
      # want to return nil here.
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
      ttl ||= self.ttl
      return if ttl.to_i.zero? # nil will be zero

      Familia.ld "#{rediskey} to #{ttl}"
      expire ttl.to_i
    end

  end

end
