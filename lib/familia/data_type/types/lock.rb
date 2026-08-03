# lib/familia/data_type/types/lock.rb
#
# frozen_string_literal: true

module Familia
  class Lock < StringKey
    def initialize(*args)
      super
      @opts[:default] = nil
    end

    # Acquire a lock with optional TTL
    #
    # With a positive ttl this is a single atomic SET NX EX command, so the
    # value and its expiry land together -- a crash can never strand a
    # permanent TTL-less lock (previously SETNX followed by EXPIRE).
    #
    # @param token [String] Unique token to identify lock holder (auto-generated if nil)
    # @param ttl [Integer, nil] Time-to-live in seconds. nil = no expiration, <=0 rejected
    # @return [String, false] Returns token if acquired successfully, false otherwise
    def acquire(token = SecureRandom.uuid, ttl: 10)
      # Reject invalid TTLs before touching the server
      return false if ttl&.<=(0)

      if ttl
        # redis-rb returns true/false for SET with NX (BoolifySet). Token goes
        # through serialize_value so held_by?/release comparisons stay
        # consistent (identity for plain strings).
        return dbclient.set(dbkey, serialize_value(token), nx: true, ex: ttl) ? token : false
      end

      # nil TTL: setnx applies the :expiration feature's default TTL via
      # update_expiration when present; otherwise the key stays TTL-less.
      success = setnx(token)
      # Handle both integer (1/0) and boolean (true/false) return values
      [1, true].include?(success) ? token : false
    end

    def release(token)
      # Lua script to atomically check token and delete
      script = "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end"
      dbclient.eval(script, [dbkey], [token]) == 1
    end

    def locked?
      !value.nil?
    end

    def held_by?(token)
      value == token
    end

    def force_unlock!
      del
    end
  end
end

Familia::DataType.register Familia::Lock, :lock
