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
      ret = redis.hset rediskey, field, serialize_value(val)
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
      deserialize_value redis.hget(rediskey, field)
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
      redis.hvals(rediskey).map { |v| deserialize_value v }
    end

    def hgetall
      redis.hgetall(rediskey).each_with_object({}) do |(k,v), ret|
        ret[k] = deserialize_value v
      end
    end
    alias all hgetall

    def key?(field)
      redis.hexists rediskey, field
    end
    alias has_key? key?
    alias include? key?
    alias member? key?

    # Removes a field from the hash
    # @param field [String] The field to remove
    # @return [Integer] The number of fields that were removed (0 or 1)
    def remove(field)
      redis.hdel rediskey, field
    end

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

      data = hsh.inject([]) { |ret, pair| ret << [pair[0], serialize_value(pair[1])] }.flatten

      ret = redis.hmset(rediskey, *data)
      update_expiration
      ret
    end
    alias merge! update

    def values_at *fields
      elements = redis.hmget(rediskey, *fields.flatten.compact)
      deserialize_values(*elements)
    end

    Familia::RedisType.register self, :hash # legacy, deprecated
    Familia::RedisType.register self, :hashkey
  end
end
