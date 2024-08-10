# frozen_string_literal: true

module Familia
  class HashKey < RedisObject
    def size
      redis.hlen rediskey
    end
    alias length size

    def empty?
      size == 0
    end

    def []=(name, val)
      ret = redis.hset rediskey, name, to_redis(val)
      update_expiration
      ret
    rescue TypeError => e
      echo :hset, caller[0] if Familia.debug
      klass = val.class
      msg = "Cannot store #{name} => #{val.inspect} (#{klass}) in #{rediskey}"
      raise e.class, msg
    end
    alias put []=
    alias store []=

    def [](name)
      from_redis redis.hget(rediskey, name)
    end
    alias get []

    def fetch(name, default = nil)
      ret = self[name]
      if ret.nil?
        raise IndexError, "No such index for: #{name}" if default.nil?

        default
      else
        ret
      end
    end

    def keys
      redis.hkeys rediskey
    end

    def values
      el = redis.hvals(rediskey)
      multi_from_redis(*el)
    end

    def all
      # TODO: Use from_redis. Also name `all` is confusing with
      # Onetime::Customer.all which returns all customers.
      redis.hgetall rediskey
    end
    alias to_hash all
    alias clone all

    def has_key?(name)
      redis.hexists rediskey, name
    end
    alias include? has_key?
    alias member? has_key?

    def delete(name)
      redis.hdel rediskey, name
    end
    alias remove delete
    alias rem delete
    alias del delete

    def increment(name, by = 1)
      redis.hincrby(rediskey, name, by).to_i
    end
    alias incr increment
    alias incrby increment

    def decrement(name, by = 1)
      increment name, -by
    end
    alias decr decrement
    alias decrby decrement

    def update(hsh = {})
      raise ArgumentError, 'Argument to bulk_set must be a hash' unless hsh.is_a?(Hash)

      data = hsh.inject([]) { |ret, pair| ret << [pair[0], to_redis(pair[1])] }.flatten

      ret = redis.hmset(rediskey, *data)
      update_expiration
      ret
    end
    alias merge! update

    def values_at *names
      el = redis.hmget(rediskey, *names.flatten.compact)
      multi_from_redis(*el)
    end

    Familia::RedisObject.register self, :hash # legacy, deprecated
    Familia::RedisObject.register self, :hashkey
  end

end
