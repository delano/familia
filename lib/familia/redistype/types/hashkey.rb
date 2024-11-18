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

    # The Great Redis Refresh-o-matic 3000 for HashKey!
    #
    # This method performs a complete refresh of the hash's state from Redis.
    # It's like giving your hash a memory transfusion - out with the old state,
    # in with the fresh data straight from Redis!
    #
    # @note This operation is atomic - it either succeeds completely or fails
    #   safely. Any unsaved changes to the hash will be overwritten.
    #
    # @return [void] Returns nothing, but your hash will be sparkling clean
    #   with all its fields synchronized with Redis.
    #
    # @raise [Familia::KeyNotFoundError] If the Redis key for this hash no
    #   longer exists. Time travelers beware!
    #
    # @example Basic usage
    #   my_hash.refresh!  # ZAP! Fresh data loaded
    #
    # @example With error handling
    #   begin
    #     my_hash.refresh!
    #   rescue Familia::KeyNotFoundError
    #     puts "Oops! Our hash seems to have vanished into the Redis void!"
    #   end
    def refresh!
      Familia.trace :REFRESH, redis, redisuri, caller(1..1) if Familia.debug?
      raise Familia::KeyNotFoundError, rediskey unless redis.exists(rediskey)

      fields = hgetall
      Familia.ld "[refresh!] #{self.class} #{rediskey} #{fields.keys}"

      # For HashKey, we update by merging the fresh data
      update(fields)
    end

    # The friendly neighborhood refresh method!
    #
    # This method is like refresh! but with better manners - it returns self
    # so you can chain it with other methods. It's perfect for when you want
    # to refresh your hash and immediately do something with it.
    #
    # @return [self] Returns the refreshed hash, ready for more adventures!
    #
    # @raise [Familia::KeyNotFoundError] If the Redis key does not exist.
    #   The hash must exist in Redis-land for this to work!
    #
    # @example Refresh and chain
    #   my_hash.refresh.keys  # Refresh and get all keys
    #   my_hash.refresh['field']  # Refresh and get a specific field
    #
    # @see #refresh! For the heavy lifting behind the scenes
    def refresh
      refresh!
      self
    end

    Familia::RedisType.register self, :hash # legacy, deprecated
    Familia::RedisType.register self, :hashkey
  end
end
