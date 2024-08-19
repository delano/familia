# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Methods that call Redis commands (InstanceMethods)
    #
    # NOTE: There is no hgetall for Horreum. This is because Horreum
    # is a single hash in Redis that we aren't meant to have be working
    # on in memory for more than, making changes -> committing. To
    # emphasize this, instead of "refreshing" the object with hgetall,
    # just load the object again.
    #
    module Commands

      def exists?
        # Trace output comes from the class method
        self.class.exists? identifier, suffix
      end

      # Sets a timeout on key. After the timeout has expired, the key will automatically be deleted.
      # Returns 1 if the timeout was set, 0 if key does not exist or the timeout could not be set.
      #
      def expire(ttl = nil)
        ttl ||= self.class.ttl
        Familia.trace :EXPIRE, redis, ttl, caller(1..1) if Familia.debug?
        redis.expire rediskey, ttl.to_i
      end

      def realttl
        Familia.trace :REALTTL, redis, redisuri, caller(1..1) if Familia.debug?
        redis.ttl rediskey
      end

      # Deletes a field from the hash stored at the Redis key.
      #
      # @param field [String] The field to delete from the hash.
      # @return [Integer] The number of fields that were removed from the hash (0 or 1).
      # @note This method is destructive, as indicated by the bang (!).
      def hdel!(field)
        Familia.trace :HDEL, redis, field, caller(1..1) if Familia.debug?
        redis.hdel rediskey, field
      end

      def redistype
        Familia.trace :REDISTYPE, redis, redisuri, caller(1..1) if Familia.debug?
        redis.type rediskey(suffix)
      end

      # Parity with RedisType#rename
      def rename(newkey)
        Familia.trace :RENAME, redis, "#{rediskey} -> #{newkey}", caller(1..1) if Familia.debug?
        redis.rename rediskey, newkey
      end

      # For parity with RedisType#hgetall
      def hgetall
        Familia.trace :HGETALL, redis, redisuri, caller(1..1) if Familia.debug?
        redis.hgetall rediskey(suffix)
      end
      alias all hgetall

      def hget(field)
        Familia.trace :HGET, redis, field, caller(1..1) if Familia.debug?
        redis.hget rediskey(suffix), field
      end

      # @return The number of fields that were added to the hash. If the
      #  field already exists, this will return 0.
      def hset(field, value)
        Familia.trace :HSET, redis, field, caller(1..1) if Familia.debug?
        redis.hset rediskey, field, value
      end

      def hmset
        redis.hmset rediskey(suffix), self.to_h
      end

      def hkeys
        Familia.trace :HKEYS, redis, 'redisuri', caller(1..1) if Familia.debug?
        redis.hkeys rediskey(suffix)
      end

      def hvals
        redis.hvals rediskey(suffix)
      end

      def incr(field)
        redis.hincrby rediskey(suffix), field, 1
      end
      alias increment incr

      def incrby(field, increment)
        redis.hincrby rediskey(suffix), field, increment
      end
      alias incrementby incrby

      def incrbyfloat(field, increment)
        redis.hincrbyfloat rediskey(suffix), field, increment
      end
      alias incrementbyfloat incrbyfloat

      def decrby(field, decrement)
        redis.decrby rediskey(suffix), field, decrement
      end
      alias decrementby decrby

      def decr(field)
        redis.hdecr field
      end
      alias decrement decr

      def hlen
        redis.hlen rediskey(suffix)
      end
      alias hlength hlen

      def hstrlen(field)
        redis.hstrlen rediskey(suffix), field
      end
      alias hstrlength hstrlen

      def key?(field)
        redis.hexists rediskey(suffix), field
      end
      alias has_key? key?

      def delete!
        Familia.trace :DELETE!, redis, redisuri, caller(1..1) if Familia.debug?
        ret = redis.del rediskey
        ret.positive?
      end
      protected :delete!

    end

    include Commands # these become Familia::Horreum instance methods
  end
end
