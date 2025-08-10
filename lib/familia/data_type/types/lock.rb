# lib/familia/data_type/types/lock.rb

module Familia
  class Lock < String
    def initialize(*args)
      super
      @opts[:default] ||= nil
    end

    def acquire(token = SecureRandom.uuid, ttl: 10)
      success = setnx(token)
      expire(ttl) if success && ttl > 0
      success ? token : false
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
