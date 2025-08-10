# lib/familia/horreum/database_commands.rb

module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Database operations and object management.
  #
  class Horreum
    # Methods that call Database commands (InstanceMethods)
    #
    # NOTE: There is no hgetall for Horreum. This is because Horreum
    # is a single hash in Database that we aren't meant to have be working
    # on in memory for more than, making changes -> committing. To
    # emphasize this, instead of "refreshing" the object with hgetall,
    # just load the object again.
    #
    module DatabaseCommands
      def move(logical_database)
        dbclient.move dbkey, logical_database
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
        key_exists = self.class.exists?(dbkey)
        return key_exists unless check_size

        key_exists && !size.zero?
      end

      # Returns the number of fields in the main object hash
      # @return [Integer] number of fields
      def field_count
        dbclient.hlen dbkey
      end
      alias size field_count

      # Sets a timeout on key. After the timeout has expired, the key will
      # automatically be deleted. Returns 1 if the timeout was set, 0 if key
      # does not exist or the timeout could not be set.
      #
      def expire(default_expiration = nil)
        default_expiration ||= self.class.default_expiration
        Familia.trace :EXPIRE, dbclient, default_expiration, caller(1..1) if Familia.debug?
        dbclient.expire dbkey, default_expiration.to_i
      end

      # Retrieves the remaining time to live (TTL) for the object's dbkey.
      #
      # This method accesses the ovjects Database client to obtain the TTL of `dbkey`.
      # If debugging is enabled, it logs the TTL retrieval operation using `Familia.trace`.
      #
      # @return [Integer] The TTL of the key in seconds. Returns -1 if the key does not exist
      #   or has no associated expire time.
      def current_expiration
        Familia.trace :CURRENT_EXPIRATION, dbclient, uri, caller(1..1) if Familia.debug?
        dbclient.ttl dbkey
      end

      # Removes a field from the hash stored at the dbkey.
      #
      # @param field [String] The field to remove from the hash.
      # @return [Integer] The number of fields that were removed from the hash (0 or 1).
      def remove_field(field)
        Familia.trace :HDEL, dbclient, field, caller(1..1) if Familia.debug?
        dbclient.hdel dbkey, field
      end
      alias remove remove_field # deprecated

      def data_type
        Familia.trace :DATATYPE, dbclient, uri, caller(1..1) if Familia.debug?
        dbclient.type dbkey(suffix)
      end

      # For parity with DataType#hgetall
      def hgetall
        Familia.trace :HGETALL, dbclient, uri, caller(1..1) if Familia.debug?
        dbclient.hgetall dbkey(suffix)
      end
      alias all hgetall

      def hget(field)
        Familia.trace :HGET, dbclient, field, caller(1..1) if Familia.debug?
        dbclient.hget dbkey(suffix), field
      end

      # @return The number of fields that were added to the hash. If the
      #  field already exists, this will return 0.
      def hset(field, value)
        Familia.trace :HSET, dbclient, field, caller(1..1) if Familia.debug?
        dbclient.hset dbkey, field, value
      end

      # Sets field in the hash stored at key to value, only if field does not yet exist.
      # If key does not exist, a new key holding a hash is created. If field already exists,
      # this operation has no effect.
      #
      # @param field [String] The field to set in the hash
      # @param value [String] The value to set for the field
      # @return [Integer] 1 if the field is a new field in the hash and the value was set,
      #   0 if the field already exists in the hash and no operation was performed
      def hsetnx(field, value)
        Familia.trace :HSETNX, dbclient, field, caller(1..1) if Familia.debug?
        dbclient.hsetnx dbkey, field, value
      end

      def hmset(hsh = {})
        hsh ||= to_h
        Familia.trace :HMSET, dbclient, hsh, caller(1..1) if Familia.debug?
        dbclient.hmset dbkey(suffix), hsh
      end

      def hkeys
        Familia.trace :HKEYS, dbclient, 'uri', caller(1..1) if Familia.debug?
        dbclient.hkeys dbkey(suffix)
      end

      def hvals
        dbclient.hvals dbkey(suffix)
      end

      def incr(field)
        dbclient.hincrby dbkey(suffix), field, 1
      end
      alias increment incr

      def incrby(field, increment)
        dbclient.hincrby dbkey(suffix), field, increment
      end
      alias incrementby incrby

      def incrbyfloat(field, increment)
        dbclient.hincrbyfloat dbkey(suffix), field, increment
      end
      alias incrementbyfloat incrbyfloat

      def decrby(field, decrement)
        dbclient.decrby dbkey(suffix), field, decrement
      end
      alias decrementby decrby

      def decr(field)
        dbclient.hdecr field
      end
      alias decrement decr

      def hstrlen(field)
        dbclient.hstrlen dbkey(suffix), field
      end
      alias hstrlength hstrlen

      def key?(field)
        dbclient.hexists dbkey(suffix), field
      end
      alias has_key? key?

      # Deletes the entire dbkey
      # @return [Boolean] true if the key was deleted, false otherwise
      def delete!
        Familia.trace :DELETE!, dbclient, uri, caller(1..1) if Familia.debug?
        ret = dbclient.del dbkey
        ret.positive?
      end
      alias clear delete!
    end
  end
end
