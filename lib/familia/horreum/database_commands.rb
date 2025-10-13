# lib/familia/horreum/database_commands.rb

module Familia
  # Familia::Horreum
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Database operations and object management.
  #
  class Horreum
    # DatabaseCommands - Instance-level methods for horreum models that call Database commands
    #
    # NOTE: There is no hgetall for Horreum. This is because Horreum
    # is a single hash in Database that we aren't meant to have be working
    # on in memory for more than, making changes -> committing. To
    # emphasize this, instead of "refreshing" the object with hgetall,
    # just load the object again.
    #
    module DatabaseCommands
      # Moves the object's key to a different logical database.
      #
      # @param logical_database [Integer] The target database number
      # @return [Boolean] true if the key was moved successfully
      def move(logical_database)
        dbclient.move dbkey, logical_database
      end

      # Checks if the calling object's key exists in the database.
      #
      # @param check_size [Boolean] When true (default), also verifies the hash has a non-zero size.
      #   When false, only checks key existence regardless of content.
      # @return [Boolean] Returns `true` if the key exists in the database. When `check_size` is true,
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
        key_exists = self.class.exists?(identifier)
        return key_exists unless check_size

        # Handle Redis::Future in transactions - skip size check
        if key_exists.is_a?(Redis::Future)
          return key_exists
        end

        current_size = size
        # Handle Redis::Future from size call too
        if current_size.is_a?(Redis::Future)
          return current_size
        end

        key_exists && !current_size.zero?
      end

      # Returns the number of fields in the main object hash
      # @return [Integer] number of fields
      def field_count
        dbclient.hlen dbkey
      end
      alias size field_count
      alias length field_count

      # Sets a timeout on key. After the timeout has expired, the key will
      # automatically be deleted. Returns 1 if the timeout was set, 0 if key
      # does not exist or the timeout could not be set.
      #
      # @param default_expiration [Integer] TTL in seconds (uses class default if nil)
      # @return [Integer] 1 if timeout was set, 0 otherwise
      def expire(default_expiration = nil)
        default_expiration ||= self.class.default_expiration
        Familia.trace :EXPIRE, nil, default_expiration if Familia.debug?
        dbclient.expire dbkey, default_expiration.to_i
      end

      # Retrieves the remaining time to live (TTL) for the object's dbkey.
      #
      # This method accesses the objects Database client to obtain the TTL of `dbkey`.
      # If debugging is enabled, it logs the TTL retrieval operation using `Familia.trace`.
      #
      # @return [Integer] The TTL of the key in seconds. Returns -1 if the key does not exist
      #   or has no associated expire time.
      def current_expiration
        Familia.trace :CURRENT_EXPIRATION, nil, self.class.uri if Familia.debug?
        dbclient.ttl dbkey
      end

      # Removes a field from the hash stored at the dbkey.
      #
      # @param field [String] The field to remove from the hash.
      # @return [Integer] The number of fields that were removed from the hash (0 or 1).
      def remove_field(field)
        Familia.trace :HDEL, nil, field if Familia.debug?
        dbclient.hdel dbkey, field
      end
      alias remove remove_field # deprecated

      # Returns the Redis data type of the key.
      #
      # @return [String] The data type (e.g., 'hash', 'string', 'list')
      def data_type
        Familia.trace :DATATYPE, nil, self.class.uri if Familia.debug?
        dbclient.type dbkey(suffix)
      end

      # Returns all fields and values in the hash.
      #
      # @return [Hash] All field-value pairs in the hash
      # @note For parity with DataType#hgetall
      def hgetall
        Familia.trace :HGETALL, nil, self.class.uri if Familia.debug?
        dbclient.hgetall dbkey(suffix)
      end
      alias all hgetall

      # Gets the value of a hash field.
      #
      # @param field [String] The field name
      # @return [String, nil] The value of the field, or nil if field doesn't exist
      def hget(field)
        Familia.trace :HGET, nil, field if Familia.debug?
        dbclient.hget dbkey(suffix), field
      end

      # Sets the value of a hash field.
      #
      # @param field [String] The field name
      # @param value [String] The value to set
      # @return [Integer] The number of fields that were added to the hash. If the
      #  field already exists, this will return 0.
      def hset(field, value)
        Familia.trace :HSET, nil, field if Familia.debug?
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
        Familia.trace :HSETNX, nil, field if Familia.debug?
        dbclient.hsetnx dbkey, field, value
      end

      # Sets multiple hash fields to multiple values.
      #
      # @param hsh [Hash] Hash of field-value pairs to set
      # @return [String] 'OK' on success
      def hmset(hsh = {})
        hsh ||= to_h_for_storage
        Familia.trace :HMSET, nil, hsh if Familia.debug?
        dbclient.hmset dbkey(suffix), hsh
      end

      # Returns all field names in the hash.
      #
      # @return [Array<String>] Array of field names
      def hkeys
        Familia.trace :HKEYS, nil, self.class.uri if Familia.debug?
        dbclient.hkeys dbkey(suffix)
      end

      # Returns all values in the hash.
      #
      # @return [Array<String>] Array of values
      def hvals
        dbclient.hvals dbkey(suffix)
      end

      # Increments the integer value of a hash field by 1.
      #
      # @param field [String] The field name
      # @return [Integer] The value after incrementing
      def incr(field)
        dbclient.hincrby dbkey(suffix), field, 1
      end
      alias increment incr

      # Increments the integer value of a hash field by the given amount.
      #
      # @param field [String] The field name
      # @param increment [Integer] The increment value
      # @return [Integer] The value after incrementing
      def incrby(field, increment)
        dbclient.hincrby dbkey(suffix), field, increment
      end
      alias incrementby incrby

      # Increments the float value of a hash field by the given amount.
      #
      # @param field [String] The field name
      # @param increment [Float] The increment value
      # @return [Float] The value after incrementing
      def incrbyfloat(field, increment)
        dbclient.hincrbyfloat dbkey(suffix), field, increment
      end
      alias incrementbyfloat incrbyfloat

      # Decrements the integer value of a hash field by the given amount.
      #
      # @param field [String] The field name
      # @param decrement [Integer] The decrement value
      # @return [Integer] The value after decrementing
      def decrby(field, decrement)
        dbclient.decrby dbkey(suffix), field, decrement
      end
      alias decrementby decrby

      # Decrements the integer value of a hash field by 1.
      #
      # @param field [String] The field name
      # @return [Integer] The value after decrementing
      def decr(field)
        dbclient.hdecr field
      end
      alias decrement decr

      # Returns the string length of the value associated with field in the hash.
      #
      # @param field [String] The field name
      # @return [Integer] The string length of the field value, or 0 if field doesn't exist
      def hstrlen(field)
        dbclient.hstrlen dbkey(suffix), field
      end
      alias hstrlength hstrlen

      # Determines if a hash field exists.
      #
      # @param field [String] The field name
      # @return [Boolean] true if the field exists, false otherwise
      def key?(field)
        dbclient.hexists dbkey(suffix), field
      end
      alias has_key? key?

      # Deletes the dbkey for this horreum :object.
      #
      # It does not delete the related fields keys. See destroy!
      #
      # @return [Boolean] true if the key was deleted, false otherwise
      def delete!
        Familia.trace :DELETE!, nil, self.class.uri if Familia.debug?

        # Delete the main object key
        dbclient.del dbkey
      end
      alias clear delete!

      # Watches the key for changes during a MULTI/EXEC transaction.
      #
      # Decision Matrix:
      #
      #   | Scenario | Use | Why |
      #   |----------|-----|-----|
      #   | Check if exists, then create | WATCH | Must prevent duplicate creation |
      #   | Read value, update conditionally | WATCH | Decision depends on current state |
      #   | Compare-and-swap operations | WATCH | Need optimistic locking |
      #   | Version-based updates | WATCH | Must detect concurrent changes |
      #   | Batch field updates | MULTI only | No conditional logic |
      #   | Increment + timestamp together | MULTI only | Concurrent increments OK |
      #   | Save object atomically | MULTI only | Just need atomicity |
      #   | Update indexes with save | MULTI only | No state checking needed |
      #
      # @param suffix_override [String, nil] Optional suffix override
      # @return [String] 'OK' on success
      def watch(...)
        raise ArgumentError, 'Block required' unless block_given?

        # Forward all arguments including the block to the watch command
        dbclient.watch(dbkey, ...)

      rescue Redis::BaseError => e
        raise OptimisticLockError, "Redis error: #{e.message}"
      end

      # Flushes all the previously watched keys for a transaction.
      #
      # If a transaction completes successfully or discard is called, there's
      # no need to manually call unwatch.
      #
      # NOTE: This command operates on the connection itself; not a specific key
      #
      # @return [String] 'OK' always, regardless of whether the key was watched or not
      def unwatch(...) = dbclient.unwatch(...)

      # Flushes all previously queued commands in a transaction and all watched keys
      #
      # NOTE: This command operates on the connection itself; not a specific key
      #
      # @return [String] 'OK' always
      def discard(...) = dbclient.discard(...)

      # Echoes a message through the Redis connection.
      #
      # @param args [Array] Arguments to join and echo
      # @return [String] The echoed message
      def echo(*args)
        dbclient.echo "[#{self.class}] #{args.join(' ')}"
      end
    end
  end
end
