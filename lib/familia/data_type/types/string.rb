# lib/familia/data_type/types/string.rb

module Familia
  class String < DataType
    def init; end

    # Returns the number of elements in the list
    # @return [Integer] number of elements
    def char_count
      to_s.size
    end
    alias size char_count
    alias length char_count

    def empty?
      char_count.zero?
    end

    def value
      echo :value, caller(0..0) if Familia.debug
      dbclient.setnx dbkey, @opts[:default] if @opts[:default]
      deserialize_value dbclient.get(dbkey)
    end
    alias content value
    alias get value

    def to_s
      return super if value.to_s.empty?

      value.to_s
    end

    def to_i
      value&.to_i || 0
    end

    def value=(val)
      ret = dbclient.set(dbkey, serialize_value(val))
      update_expiration
      ret
    end
    alias replace value=
    alias set value=

    def setnx(val)
      ret = dbclient.setnx(dbkey, serialize_value(val))
      update_expiration
      ret
    end

    def increment
      ret = dbclient.incr(dbkey)
      update_expiration
      ret
    end
    alias incr increment

    def incrementby(val)
      ret = dbclient.incrby(dbkey, val.to_i)
      update_expiration
      ret
    end
    alias incrby incrementby

    def decrement
      ret = dbclient.decr dbkey
      update_expiration
      ret
    end
    alias decr decrement

    def decrementby(val)
      ret = dbclient.decrby dbkey, val.to_i
      update_expiration
      ret
    end
    alias decrby decrementby

    def append(val)
      ret = dbclient.append dbkey, val
      update_expiration
      ret
    end
    alias << append

    def getbit(offset)
      dbclient.getbit dbkey, offset
    end

    def setbit(offset, val)
      ret = dbclient.setbit dbkey, offset, val
      update_expiration
      ret
    end

    def getrange(spoint, epoint)
      dbclient.getrange dbkey, spoint, epoint
    end

    def setrange(offset, val)
      ret = dbclient.setrange dbkey, offset, val
      update_expiration
      ret
    end

    def getset(val)
      ret = dbclient.getset dbkey, val
      update_expiration
      ret
    end

    def del
      ret = dbclient.del dbkey
      ret.positive?
    end

    def nil?
      value.nil?
    end

    Familia::DataType.register self, :string
  end
end

# Both subclass String
require_relative 'lock'
require_relative 'counter'
