# lib/familia/horreum/commands.rb

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

      def move(logical_database)
        redis.move rediskey, logical_database
      end

      # Checks if the calling object's key exists in Redis.
      #
      # @param check_size [Boolean] When true (default), also verifies the hash has a non-zero size.
      #   When false, only checks key existence regardless of content.
      # @return [Boolean] Returns `true` if the key exists in Redis. When `check_size` is true,
      #   also requires the hash to have at least one field.
      #
      # @example Check existence with size validation (default behavior)
      #   some_object.exists?                    # => false for empty hashes
      #   some_object.exists?(check_size: true)  # => false for empty hashes
      #
      # @example Check existence only
      #   some_object.exists?(check_size: false)  # => true for empty hashes
      #
      # @note The default behavior maintains backward compatibility by treating empty hashes
      #   as non-existent. Use `check_size: false` for pure key existence checking.
      def exists?(check_size: true)
        key_exists = self.class.redis.exists?(rediskey)
        return key_exists unless check_size
        key_exists && !size.zero?
      end

      # Returns the number of fields in the main object hash
      # @return [Integer] number of fields
      def field_count
        redis.hlen rediskey
      end
      alias size field_count

      # Sets a timeout on key. After the timeout has expired, the key will
      # automatically be deleted. Returns 1 if the timeout was set, 0 if key
      # does not exist or the timeout could not be set.
      #
      def expire(default_expiration = nil)
        default_expiration ||= self.class.default_expiration
        Familia.trace :EXPIRE, redis, default_expiration, caller(1..1) if Familia.debug?
        redis.expire rediskey, default_expiration.to_i
      end

      # Retrieves the remaining time to live (TTL) for the object's Redis key.
      #
      # This method accesses the ovjects Redis client to obtain the TTL of `rediskey`.
      # If debugging is enabled, it logs the TTL retrieval operation using `Familia.trace`.
      #
      # @return [Integer] The TTL of the key in seconds. Returns -1 if the key does not exist
      #   or has no associated expire time.
      def current_expiration
        Familia.trace :CURRENT_EXPIRATION, redis, redisuri, caller(1..1) if Familia.debug?
        redis.ttl rediskey
      end

      # Removes a field from the hash stored at the Redis key.
      #
      # @param field [String] The field to remove from the hash.
      # @return [Integer] The number of fields that were removed from the hash (0 or 1).
      def remove_field(field)
        Familia.trace :HDEL, redis, field, caller(1..1) if Familia.debug?
        redis.hdel rediskey, field
      end
      alias remove remove_field # deprecated

      def redistype
        Familia.trace :REDISTYPE, redis, redisuri, caller(1..1) if Familia.debug?
        redis.type rediskey(suffix)
      end

      # Parity with RedisType#rename
      def rename(newkey)
        Familia.trace :RENAME, redis, "#{rediskey} -> #{newkey}", caller(1..1) if Familia.debug?
        redis.rename rediskey, newkey
      end

      # Retrieves the prefix for the current instance by delegating to its class.
      #
      # @return [String] The prefix associated with the class of the current instance.
      # @example
      #   instance.prefix
      def prefix
        self.class.prefix
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

      def hmset(hsh={})
        hsh ||= self.to_h
        Familia.trace :HMSET, redis, hsh, caller(1..1) if Familia.debug?
        redis.hmset rediskey(suffix), hsh
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

      def hstrlen(field)
        redis.hstrlen rediskey(suffix), field
      end
      alias hstrlength hstrlen

      def key?(field)
        redis.hexists rediskey(suffix), field
      end
      alias has_key? key?

      # Deletes the entire Redis key
      # @return [Boolean] true if the key was deleted, false otherwise
      def delete!
        Familia.trace :DELETE!, redis, redisuri, caller(1..1) if Familia.debug?
        ret = redis.del rediskey
        ret.positive?
      end
      alias clear delete!

    end

    include Commands # these become Familia::Horreum instance methods
  end
end
