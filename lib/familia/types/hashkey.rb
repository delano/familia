# frozen_string_literal: true

module Familia
  class HashKey < RedisType
    def size
      redis.hlen rediskey
    end
    alias length size

    def empty?
      size.zero?
    end

    # +return+ [Integer] Returns 1 if the field is new and added, 0 if the
    #  field already existed and the value was updated.
    def []=(field, val)
      ret = redis.hset rediskey, field, to_redis(val)
      update_expiration
      ret
    rescue TypeError => e
      Familia.le "[hset]= #{e.message}"
      Familia.ld "[hset]= #{rediskey} #{field}=#{val}" if Familia.debug
      echo :hset, caller(1..1).first if Familia.debug # logs via echo to redis and back
      klass = val.class
      msg = "Cannot store #{field} => #{val.inspect} (#{klass}) in #{rediskey}"
      raise e.class, msg
    end
    alias put []=
    alias store []=

    def [](field)
      from_redis redis.hget(rediskey, field)
    end
    alias get []

    def fetch(field, default = nil)
      ret = self[field]
      if ret.nil?
        raise IndexError, "No such index for: #{field}" if default.nil?

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

    def hgetall
      # TODO: Use from_redis. Also name `all` is confusing with
      # Onetime::Customer.all which returns all customers.
      redis.hgetall rediskey
    end
    alias all hgetall
    alias to_hash hgetall
    alias clone hgetall

    def has_key?(field)
      redis.hexists rediskey, field
    end
    alias include? has_key?
    alias member? has_key?

    def delete(field)
      redis.hdel rediskey, field
    end
    alias remove delete
    alias rem delete
    alias del delete

    def increment(field, by = 1)
      redis.hincrby(rediskey, field, by).to_i
    end
    alias incr increment
    alias incrby increment

    def decrement(field, by = 1)
      increment field, -by
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

    def values_at *fields
      el = redis.hmget(rediskey, *fields.flatten.compact)
      multi_from_redis(*el)
    end

    Familia::RedisType.register self, :hash # legacy, deprecated
    Familia::RedisType.register self, :hashkey
  end
end
