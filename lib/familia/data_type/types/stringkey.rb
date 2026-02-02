# lib/familia/data_type/types/stringkey.rb
#
# frozen_string_literal: true

module Familia
  class StringKey < DataType
    def init; end

    # StringKey uses raw string serialization (not JSON) because Redis string
    # operations like INCR, DECR, APPEND operate on raw values.
    # This overrides the base JSON serialization from DataType.
    def serialize_value(val)
      Familia.trace :TOREDIS, nil, "#{val}<#{val.class}>" if Familia.debug?

      # Handle Familia object references - extract identifier
      if val.is_a?(Familia::Base) || (val.is_a?(Class) && val.ancestors.include?(Familia::Base))
        return val.is_a?(Class) ? val.name : val.identifier
      end

      # StringKey uses raw string conversion for Redis compatibility
      val.to_s
    end

    # StringKey returns raw values (not JSON parsed)
    def deserialize_value(val)
      return val if val.is_a?(Redis::Future)
      return @opts[:default] if val.nil?
      val
    end

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
      echo :value, Familia.pretty_stack(limit: 1) if Familia.debug
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
      value.to_i
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

    # Atomically get and delete the value
    # @return [String, nil] The value before deletion, or nil if key didn't exist
    def getdel
      dbclient.getdel(dbkey)
    end

    # Get value and optionally set expiration atomically
    # @param ex [Integer, nil] Set expiration in seconds
    # @param px [Integer, nil] Set expiration in milliseconds
    # @param exat [Integer, nil] Set expiration at Unix timestamp (seconds)
    # @param pxat [Integer, nil] Set expiration at Unix timestamp (milliseconds)
    # @param persist [Boolean] Remove existing expiration
    # @return [String, nil] The value
    def getex(ex: nil, px: nil, exat: nil, pxat: nil, persist: false)
      options = {}
      options[:ex] = ex if ex
      options[:px] = px if px
      options[:exat] = exat if exat
      options[:pxat] = pxat if pxat
      options[:persist] = persist if persist

      dbclient.getex(dbkey, **options)
    end

    # Increment value by a float amount
    # @param val [Float, Numeric] The amount to increment by
    # @return [Float] The new value after increment
    def incrbyfloat(val)
      ret = dbclient.incrbyfloat(dbkey, val.to_f)
      update_expiration
      ret
    end
    alias incrfloat incrbyfloat

    # Set value with expiration in seconds
    # @param seconds [Integer] Expiration time in seconds
    # @param val [Object] The value to set
    # @return [String] "OK" on success
    def setex(seconds, val)
      dbclient.setex(dbkey, seconds.to_i, serialize_value(val))
    end

    # Set value with expiration in milliseconds
    # @param milliseconds [Integer] Expiration time in milliseconds
    # @param val [Object] The value to set
    # @return [String] "OK" on success
    def psetex(milliseconds, val)
      dbclient.psetex(dbkey, milliseconds.to_i, serialize_value(val))
    end

    # Count the number of set bits (population counting)
    # @param start_pos [Integer, nil] Start byte position (optional)
    # @param end_pos [Integer, nil] End byte position (optional)
    # @return [Integer] Number of bits set to 1
    def bitcount(start_pos = nil, end_pos = nil)
      if start_pos && end_pos
        dbclient.bitcount(dbkey, start_pos, end_pos)
      elsif start_pos
        dbclient.bitcount(dbkey, start_pos)
      else
        dbclient.bitcount(dbkey)
      end
    end

    # Find the position of the first bit set to 0 or 1
    # @param bit [Integer] The bit value to search for (0 or 1)
    # @param start_pos [Integer, nil] Start byte position (optional)
    # @param end_pos [Integer, nil] End byte position (optional)
    # @return [Integer] Position of the first bit, or -1 if not found
    def bitpos(bit, start_pos = nil, end_pos = nil)
      if start_pos && end_pos
        dbclient.bitpos(dbkey, bit, start_pos, end_pos)
      elsif start_pos
        dbclient.bitpos(dbkey, bit, start_pos)
      else
        dbclient.bitpos(dbkey, bit)
      end
    end

    # Perform bitfield operations on this string
    # @param args [Array] Bitfield subcommands and arguments
    # @return [Array] Results of the bitfield operations
    # @example Get an unsigned 8-bit integer at offset 0
    #   str.bitfield('GET', 'u8', 0)
    # @example Set and increment
    #   str.bitfield('SET', 'u8', 0, 100, 'INCRBY', 'i5', 100, 1)
    def bitfield(*args)
      ret = dbclient.bitfield(dbkey, *args)
      update_expiration
      ret
    end

    def del
      ret = dbclient.del dbkey
      ret.positive?
    end

    # Class methods for multi-key operations
    class << self
      # Get values for multiple keys
      # @param keys [Array<String>] Full Redis key names
      # @param client [Redis, nil] Optional Redis client (uses Familia.dbclient if nil)
      # @return [Array] Values for each key (nil for non-existent keys)
      # @example
      #   StringKey.mget('user:1:name', 'user:2:name')
      def mget(*keys, client: nil)
        client ||= Familia.dbclient
        client.mget(*keys)
      end

      # Set multiple keys atomically.
      # Keys and values are extracted from the hash for the Redis MSET command.
      #
      # @param hash [Hash] Key-value pairs to set
      # @param client [Redis, nil] Optional Redis client (uses Familia.dbclient if nil)
      # @return [String] "OK" on success
      # @example
      #   StringKey.mset('user:1:name' => 'Alice', 'user:2:name' => 'Bob')
      def mset(hash, client: nil)
        client ||= Familia.dbclient
        client.mset(*hash.flatten)
      end

      # Set multiple keys only if none of them exist.
      # Keys and values are extracted from the hash for the Redis MSETNX command.
      #
      # @param hash [Hash] Key-value pairs to set
      # @param client [Redis, nil] Optional Redis client (uses Familia.dbclient if nil)
      # @return [Boolean] true if all keys were set, false if none were set
      # @example
      #   StringKey.msetnx('user:1:name' => 'Alice', 'user:2:name' => 'Bob')
      def msetnx(hash, client: nil)
        client ||= Familia.dbclient
        client.msetnx(*hash.flatten)
      end

      # Perform bitwise operations between strings and store result
      # @param operation [String, Symbol] Bitwise operation: AND, OR, XOR, NOT
      # @param destkey [String] Destination key to store result
      # @param keys [Array<String>] Source keys for the operation
      # @param client [Redis, nil] Optional Redis client (uses Familia.dbclient if nil)
      # @return [Integer] Size of the resulting string in bytes
      # @example
      #   StringKey.bitop(:and, 'result', 'key1', 'key2')
      def bitop(operation, destkey, *keys, client: nil)
        client ||= Familia.dbclient
        client.bitop(operation.to_s.upcase, destkey, *keys)
      end
    end

    Familia::DataType.register self, :string
    Familia::DataType.register self, :stringkey
  end
end

# Both subclass StringKey
require_relative 'lock'
require_relative 'counter'
