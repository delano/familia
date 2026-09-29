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
      if Familia.transaction_or_pipeline?
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
    # Unlike the other Lock methods, release can be queued inside a
    # transaction or pipeline, for example as the last command of the block
    # the lock protects. The ownership check and the delete run in one
    # server-side script, so the queued release deletes the lock only if
    # +token+ holds it when the script runs. The outcome is known only after
    # the block: the returned Future is truthy whether or not the lock was
    # released, so read its value after the block instead of testing it
    # inside.
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

    # @return [Boolean] whether any token holds the lock
    # @raise [Familia::OperationModeError] inside a transaction or pipeline,
    #   where the GET returns a Redis::Future. The Future is truthy, so a
    #   caller testing it would act as though the lock were held.
    def locked?
      Familia.assert_replies_available!('Lock#locked?')

      !value.nil?
    end

    # @param token [String] the token returned by #acquire
    # @return [Boolean] whether +token+ holds the lock
    # @raise [Familia::OperationModeError] inside a transaction or pipeline,
    #   where the GET returns a Redis::Future. The Future is truthy, so a
    #   caller testing it would proceed as the owner whatever token it holds.
    def held_by?(token)
      Familia.assert_replies_available!('Lock#held_by?')

      value == token
    end

    # The inverse of #locked?, inherited from StringKey and refused inside a
    # block for the same reason.
    #
    # @return [Boolean] whether no token holds the lock
    # @raise [Familia::OperationModeError] inside a transaction or pipeline,
    #   where StringKey#empty? would return the GET Future. The Future is
    #   truthy, so a caller testing it would treat a held lock as free.
    def empty?
      Familia.assert_replies_available!('Lock#empty?')

      super
    end

    def force_unlock!
      del
    end
  end
end

Familia::DataType.register Familia::Lock, :lock
