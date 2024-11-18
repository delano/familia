# frozen_string_literal: true

module Familia
  class String < RedisType
    def init; end

    def size
      to_s.size
    end
    alias length size

    def empty?
      size.zero?
    end

    def value
      echo :value, caller(0..0) if Familia.debug
      redis.setnx rediskey, @opts[:default] if @opts[:default]
      deserialize_value redis.get(rediskey)
    end
    alias content value
    alias get value

    def to_s
      value.to_s # value can return nil which to_s should not
    end

    def to_i
      value.to_i
    end

    def value=(val)
      ret = redis.set(rediskey, serialize_value(val))
      update_expiration
      ret
    end
    alias replace value=
    alias set value=

    def setnx(val)
      ret = redis.setnx(rediskey, serialize_value(val))
      update_expiration
      ret
    end

    def increment
      ret = redis.incr(rediskey)
      update_expiration
      ret
    end
    alias incr increment

    def incrementby(val)
      ret = redis.incrby(rediskey, val.to_i)
      update_expiration
      ret
    end
    alias incrby incrementby

    def decrement
      ret = redis.decr rediskey
      update_expiration
      ret
    end
    alias decr decrement

    def decrementby(val)
      ret = redis.decrby rediskey, val.to_i
      update_expiration
      ret
    end
    alias decrby decrementby

    def append(val)
      ret = redis.append rediskey, val
      update_expiration
      ret
    end
    alias << append

    def getbit(offset)
      redis.getbit rediskey, offset
    end

    def setbit(offset, val)
      ret = redis.setbit rediskey, offset, val
      update_expiration
      ret
    end

    def getrange(spoint, epoint)
      redis.getrange rediskey, spoint, epoint
    end

    def setrange(offset, val)
      ret = redis.setrange rediskey, offset, val
      update_expiration
      ret
    end

    def getset(val)
      ret = redis.getset rediskey, val
      update_expiration
      ret
    end

    def nil?
      value.nil?
    end

    Familia::RedisType.register self, :string
    Familia::RedisType.register self, :counter
    Familia::RedisType.register self, :lock
  end
end
