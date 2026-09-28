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
    # @raise [Familia::OperationModeError] inside a transaction or pipeline,
    #   where the SET is only queued and returns a Redis::Future -- ownership
    #   cannot be decided before EXEC, so a truthy Future would report a lock
    #   as acquired while another holder still owns it
    def acquire(token = nil, ttl: 10)
      if Fiber[:familia_transaction] || Fiber[:familia_pipeline]
        raise Familia::OperationModeError,
              'Lock#acquire cannot run inside a transaction or pipeline: ' \
              'the NX verdict resolves at EXEC, after the caller has already ' \
              'proceeded. Acquire the lock outside the block.'
      end

      # An explicitly passed nil would serialize to "" -- honor the documented
      # auto-generation contract instead.
      token ||= SecureRandom.uuid

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

    # Deletes the lock only if +token+ still holds it.
    #
    # Safe to queue inside a transaction: the ownership check and the delete
    # run together in one server-side script.
    #
    # @param token [String] the token returned by #acquire
    # @return [Boolean, Redis::Future] true when the lock was released.
    #   Inside a transaction or pipeline, the EVAL Future (resolves to 1 when
    #   released, 0 otherwise).
    def release(token)
      # Lua script to atomically check token and delete
      script = "if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end"
      Familia.transform_reply(dbclient.eval(script, [dbkey], [token])) { |reply| reply == 1 }
    end

    # @return [Boolean, Redis::Future] whether any token holds the lock.
    #   Inside a transaction or pipeline, the GET Future (resolves to the
    #   stored token or nil).
    def locked?
      Familia.transform_reply(value) { |val| !val.nil? }
    end

    # @return [Boolean, Redis::Future] whether +token+ holds the lock. Inside
    #   a transaction or pipeline, the GET Future (resolves to the stored
    #   token or nil).
    def held_by?(token)
      Familia.transform_reply(value) { |val| val == token }
    end

    def force_unlock!
      del
    end
  end
end

Familia::DataType.register Familia::Lock, :lock
