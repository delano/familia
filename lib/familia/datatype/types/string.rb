# lib/familia/datatype/types/string.rb

module Familia
  class String < DataType
    def init; end

    # Returns the number of elements in the list
    # @return [Integer] number of elements
    def char_count
      to_s.size
    end
    alias size char_count

    def empty?
      char_count.zero?
    end

    def value
      echo :value, caller(0..0) if Familia.debug
      redis.setnx dbkey, @opts[:default] if @opts[:default]
      deserialize_value redis.get(dbkey)
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
      ret = redis.set(dbkey, serialize_value(val))
      update_expiration
      ret
    end
    alias replace value=
    alias set value=

    def setnx(val)
      ret = redis.setnx(dbkey, serialize_value(val))
      update_expiration
      ret
    end

    def increment
      ret = redis.incr(dbkey)
      update_expiration
      ret
    end
    alias incr increment

    def incrementby(val)
      ret = redis.incrby(dbkey, val.to_i)
      update_expiration
      ret
    end
    alias incrby incrementby

    def decrement
      ret = redis.decr dbkey
      update_expiration
      ret
    end
    alias decr decrement

    def decrementby(val)
      ret = redis.decrby dbkey, val.to_i
      update_expiration
      ret
    end
    alias decrby decrementby

    def append(val)
      ret = redis.append dbkey, val
      update_expiration
      ret
    end
    alias << append

    def getbit(offset)
      redis.getbit dbkey, offset
    end

    def setbit(offset, val)
      ret = redis.setbit dbkey, offset, val
      update_expiration
      ret
    end

    def getrange(spoint, epoint)
      redis.getrange dbkey, spoint, epoint
    end

    def setrange(offset, val)
      ret = redis.setrange dbkey, offset, val
      update_expiration
      ret
    end

    def getset(val)
      ret = redis.getset dbkey, val
      update_expiration
      ret
    end

    def nil?
      value.nil?
    end

    Familia::DataType.register self, :string
    Familia::DataType.register self, :counter
    Familia::DataType.register self, :lock
  end
end
