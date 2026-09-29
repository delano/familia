# lib/familia/data_type/types/counter.rb
#
# frozen_string_literal: true

module Familia
  class Counter < StringKey
    def initialize(*args)
      super
      @opts[:default] ||= 0
    end

    # Enhanced counter semantics
    #
    # @return [Boolean, Redis::Future] true when SET replied OK. Inside a
    #   transaction or pipeline, the SET Future (resolves to "OK").
    def reset(val = 0)
      Familia.transform_reply(set(val)) { |reply| reply.to_s.eql?('OK') }
    end

    # Increments the counter by +amount+ only while its value is below
    # +threshold+, atomically, server-side.
    #
    # @param threshold [Integer] the exclusive upper bound checked before
    #   incrementing
    # @param amount [Integer] the increment
    # @return [Integer, false] the new value, or false when the counter had
    #   already reached +threshold+
    # @raise [Familia::OperationModeError] inside a transaction or pipeline,
    #   where the EVAL is only queued and returns a Redis::Future. Callers
    #   branch on the verdict (for example to enforce a rate limit), and a
    #   truthy Future would report the increment as allowed before it runs.
    def increment_if_less_than(threshold, amount = 1)
      Familia.assert_replies_available!('Counter#increment_if_less_than')

      lua = <<~LUA
        local current = tonumber(redis.call('GET', KEYS[1]) or '0')
        if current < tonumber(ARGV[1]) then
          return redis.call('INCRBY', KEYS[1], ARGV[2])
        end
        return nil
      LUA
      result = dbclient.eval(lua, keys: [dbkey], argv: [threshold, amount])
      if result
        update_expiration
        result.to_i
      else
        false
      end
    end

    def atomic_increment_and_get(amount = 1)
      incrementby(amount)
    end

    # Override to ensure integer serialization
    def value=(val)
      super(val.to_i)
    end

    # @return [Integer, Redis::Future] the counter value. Inside a
    #   transaction or pipeline, the GET Future (resolves to the raw value).
    def value
      Familia.transform_reply(super, &:to_i)
    end
  end
end

Familia::DataType.register Familia::Counter, :counter
