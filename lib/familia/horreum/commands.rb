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
        ret = redis.exists rediskey
        ret.positive? # differs from redis API but I think it's okay bc `exists?` is a predicate method.
      end

      # Sets a timeout on key. After the timeout has expired, the key will automatically be deleted.
      # Returns 1 if the timeout was set, 0 if key does not exist or the timeout could not be set.
      #
      def expire(ttl = nil)
        ttl ||= self.class.ttl
        redis.expire rediskey, ttl.to_i
      end

      def realttl
        redis.ttl rediskey
      end

      def hdel!(field)
        redis.hdel rediskey, field
      end

      def redistype
        redis.type rediskey(suffix)
      end

      # Parity with RedisType#rename
      def rename(newkey)
        redis.rename rediskey, newkey
      end

      # For parity with RedisType#hgetall
      def hgetall
        Familia.trace :HGETALL, redis, redisuri, caller(1..1) if Familia.debug?
        redis.hgetall rediskey(suffix)
      end
      alias all hgetall

      def hget(field)
        redis.hget rediskey(suffix), field
      end

      # @return The number of fields that were added to the hash. If the
      #  field already exists, this will return 0.
      def hset(field, value)
        Familia.trace :HSET, redis, redisuri, caller(1..1) if Familia.debug?
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

      def hincrby(field, increment)
        redis.hincrby rediskey(suffix), field, increment
      end

      def hincrbyfloat(field, increment)
        redis.hincrbyfloat rediskey(suffix), field, increment
      end

      def hlen
        redis.hlen rediskey(suffix)
      end

      def hstrlen(field)
        redis.hstrlen rediskey(suffix), field
      end

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
