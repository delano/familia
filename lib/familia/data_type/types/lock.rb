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
    # @param token [String] Unique token to identify lock holder (auto-generated if nil)
    # @param ttl [Integer, nil] Time-to-live in seconds. nil = no expiration, <=0 rejected
    # @return [String, false] Returns token if acquired successfully, false otherwise
    def acquire(token = SecureRandom.uuid, ttl: 10)
      success = setnx(token)
      # Handle both integer (1/0) and boolean (true/false) return values
      return false unless [1, true].include?(success)
      return del && false if ttl&.<=(0)
      return del && false if ttl&.positive? && !expire(ttl)

      token
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
