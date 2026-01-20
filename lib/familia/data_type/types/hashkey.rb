# lib/familia/data_type/types/hashkey.rb
#
# frozen_string_literal: true

module Familia
  class HashKey < DataType
    # Returns the number of fields in the hash
    # @return [Integer] number of fields
    def field_count
      dbclient.hlen dbkey
    end
    alias size field_count
    alias length field_count
    alias count field_count

    def empty?
      field_count.zero?
    end

    # +return+ [Integer] Returns 1 if the field is new and added, 0 if the
    #  field already existed and the value was updated.
    def []=(field, val)
      ret = dbclient.hset dbkey, field.to_s, serialize_value(val)
      update_expiration
      ret
    rescue TypeError => e
      Familia.error "[hset]= #{e.message}"
      Familia.debug "[hset]= #{dbkey} #{field}=#{val}"
      echo :hset, Familia.pretty_stack(limit: 1) if Familia.debug # logs via echo to the db and back
      klass = val.class
      msg = "Cannot store #{field} => #{val.inspect} (#{klass}) in #{dbkey}"
      raise e.class, msg
    end
    alias put []=
    alias store []=
    alias add []=

    def [](field)
      deserialize_value dbclient.hget(dbkey, field.to_s)
    end
    alias get []

    def fetch(field, default = nil)
      ret = self[field.to_s]
      if ret.nil?
        raise IndexError, "No such index for: #{field}" if default.nil?

        default
      else
        ret
      end
    end

    def keys
      dbclient.hkeys dbkey
    end

    def values
      dbclient.hvals(dbkey).map { |v| deserialize_value v }
    end

    def hgetall
      dbclient.hgetall(dbkey).transform_values do |v|
        deserialize_value v
      end
    end
    alias all hgetall

    # Sets field in the hash stored at key to value, only if field does not yet exist.
    # If field already exists, this operation has no effect.
    # @param field [String] The field name
    # @param val [Object] The value to set
    # @return [Integer] 1 if field is a new field and value was set, 0 if field already exists
    def hsetnx(field, val)
      ret = dbclient.hsetnx dbkey, field.to_s, serialize_value(val)
      update_expiration if ret == 1
      ret
    rescue TypeError => e
      Familia.error "[hsetnx] #{e.message}"
      Familia.debug "[hsetnx] #{dbkey} #{field}=#{val}"
      echo :hsetnx, Familia.pretty_stack(limit: 1) if Familia.debug # logs via echo to the db and back
      klass = val.class
      msg = "Cannot store #{field} => #{val.inspect} (#{klass}) in #{dbkey}"
      raise e.class, msg
    end

    def key?(field)
      dbclient.hexists dbkey, field.to_s
    end
    alias has_key? key?
    alias include? key?
    alias member? key?

    # Removes a field from the hash
    # @param field [String] The field to remove
    # @return [Integer] The number of fields that were removed (0 or 1)
    def remove_field(field)
      dbclient.hdel dbkey, field.to_s
    end
    alias remove remove_field
    alias remove_element remove_field

    def increment(field, by = 1)
      dbclient.hincrby(dbkey, field.to_s, by).to_i
    end
    alias incr increment
    alias incrby increment

    def decrement(field, by = 1)
      increment field, -by
    end
    alias decr decrement
    alias decrby decrement

    def update(hsh = {})
      raise ArgumentError, 'Argument to bulk_set must be a hash' unless hsh.is_a?(Hash)

      data = hsh.inject([]) { |ret, pair| ret << [pair[0], serialize_value(pair[1])] }.flatten

      ret = dbclient.hmset(dbkey, *data)
      update_expiration
      ret
    end
    alias merge! update

    def values_at *fields
      string_fields = fields.flatten.compact.map(&:to_s)
      elements = dbclient.hmget(dbkey, *string_fields)
      deserialize_values(*elements)
    end

    # Incrementally iterates over fields in the hash using cursor-based iteration.
    # This is more memory-efficient than `hgetall` for large hashes.
    #
    # @param cursor [Integer] The cursor position to start from (0 for initial call)
    # @param match [String, nil] Optional glob-style pattern to filter field names
    # @param count [Integer, nil] Optional hint for number of elements to return per call
    # @return [Array<String, Hash>] A two-element array: [new_cursor, {field => value, ...}]
    #   When new_cursor is "0", iteration is complete.
    #
    # @example Basic iteration
    #   cursor = 0
    #   loop do
    #     cursor, results = my_hash.scan(cursor)
    #     results.each { |field, value| puts "#{field}: #{value}" }
    #     break if cursor == "0"
    #   end
    #
    # @example With pattern matching
    #   cursor, results = my_hash.scan(0, match: "user:*", count: 100)
    def scan(cursor = 0, match: nil, count: nil)
      args = [dbkey, cursor]
      args += ['MATCH', match] if match
      args += ['COUNT', count] if count

      new_cursor, pairs = dbclient.hscan(*args)

      # pairs is an array of [field, value] pairs, convert to hash with deserialization
      result_hash = pairs.to_h.transform_values { |v| deserialize_value(v) }

      [new_cursor, result_hash]
    end
    alias hscan scan

    # Increments the float value of a hash field by the given amount.
    #
    # @param field [String] The field name
    # @param by [Float, Integer] The amount to increment by (can be negative)
    # @return [Float] The new value after incrementing
    #
    # @example
    #   my_hash.incrbyfloat('temperature', 0.5)  #=> 23.5
    #   my_hash.incrbyfloat('temperature', -1.2) #=> 22.3
    def incrbyfloat(field, by)
      dbclient.hincrbyfloat(dbkey, field.to_s, by).to_f
    end
    alias incrfloat incrbyfloat

    # Returns the string length of the value associated with field.
    #
    # @param field [String] The field name
    # @return [Integer] The length of the value in bytes, or 0 if field does not exist
    #
    # @example
    #   my_hash['name'] = 'Alice'
    #   my_hash.strlen('name')  #=> 7 (includes JSON quotes: "Alice")
    def strlen(field)
      dbclient.hstrlen(dbkey, field.to_s)
    end
    alias hstrlen strlen

    # Returns one or more random fields from the hash.
    #
    # @param count [Integer, nil] Number of fields to return. If nil, returns a single field.
    #   If positive, returns distinct fields. If negative, allows duplicates.
    # @param withvalues [Boolean] If true, returns fields with their values
    # @return [String, Array<String>, Array<Array>] Depending on arguments:
    #   - No count: single field name (or nil if hash is empty)
    #   - With count: array of field names
    #   - With count and withvalues: array of [field, value] pairs
    #
    # @example Get a single random field
    #   my_hash.randfield  #=> "some_field"
    #
    # @example Get 3 distinct random fields
    #   my_hash.randfield(3)  #=> ["field1", "field2", "field3"]
    #
    # @example Get 2 random fields with values
    #   my_hash.randfield(2, withvalues: true)  #=> [["field1", value1], ["field2", value2]]
    def randfield(count = nil, withvalues: false)
      if count.nil?
        dbclient.hrandfield(dbkey)
      elsif withvalues
        pairs = dbclient.hrandfield(dbkey, count, 'WITHVALUES')
        # pairs is array of [field, value, field, value, ...]
        # Convert to array of [field, deserialized_value] pairs
        pairs.each_slice(2).map { |field, val| [field, deserialize_value(val)] }
      else
        dbclient.hrandfield(dbkey, count)
      end
    end
    alias hrandfield randfield

    # -----------------------------------------------------------------------
    # Field-Level Expiration Methods (Redis 7.4+)
    #
    # These methods require Redis/Valkey 7.4 or later. They allow setting
    # TTL on individual hash fields rather than the entire key.
    # -----------------------------------------------------------------------

    # Sets expiration time in seconds on one or more hash fields.
    # @note Requires Redis 7.4+
    #
    # @param seconds [Integer] TTL in seconds
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of results for each field:
    #   -2 if field does not exist, 1 if expiration was set,
    #   0 if expiration was not set (e.g., field has no expiration)
    #
    # @example Set 1 hour TTL on specific fields
    #   my_hash.expire_fields(3600, 'session_token', 'temp_data')
    def expire_fields(seconds, *fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HEXPIRE', dbkey, seconds, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hexpire expire_fields

    # Sets expiration time in milliseconds on one or more hash fields.
    # @note Requires Redis 7.4+
    #
    # @param milliseconds [Integer] TTL in milliseconds
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of results for each field
    #
    # @example Set 500ms TTL on a field
    #   my_hash.pexpire_fields(500, 'rate_limit_counter')
    def pexpire_fields(milliseconds, *fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HPEXPIRE', dbkey, milliseconds, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hpexpire pexpire_fields

    # Sets absolute expiration time (Unix timestamp in seconds) on hash fields.
    # @note Requires Redis 7.4+
    #
    # @param unix_time [Integer] Absolute Unix timestamp in seconds
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of results for each field
    #
    # @example Expire fields at midnight tonight
    #   midnight = Time.now.to_i + (24 * 60 * 60)
    #   my_hash.expireat_fields(midnight, 'daily_counter')
    def expireat_fields(unix_time, *fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HEXPIREAT', dbkey, unix_time, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hexpireat expireat_fields

    # Sets absolute expiration time (Unix timestamp in milliseconds) on hash fields.
    # @note Requires Redis 7.4+
    #
    # @param unix_time_ms [Integer] Absolute Unix timestamp in milliseconds
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of results for each field
    #
    # @example Expire field at a precise millisecond
    #   my_hash.pexpireat_fields(1700000000000, 'precise_data')
    def pexpireat_fields(unix_time_ms, *fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HPEXPIREAT', dbkey, unix_time_ms, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hpexpireat pexpireat_fields

    # Returns the remaining TTL in seconds for one or more hash fields.
    # @note Requires Redis 7.4+
    #
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of TTL values for each field:
    #   -2 if field does not exist, -1 if field has no expiration,
    #   otherwise the TTL in seconds
    #
    # @example Check remaining TTL on fields
    #   my_hash.ttl_fields('session_token', 'temp_data')  #=> [3600, -1]
    def ttl_fields(*fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HTTL', dbkey, 'FIELDS', string_fields.size, *string_fields)
    end
    alias httl ttl_fields

    # Returns the remaining TTL in milliseconds for one or more hash fields.
    # @note Requires Redis 7.4+
    #
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of TTL values in milliseconds
    #
    # @example Check remaining TTL in milliseconds
    #   my_hash.pttl_fields('rate_limit')  #=> [450]
    def pttl_fields(*fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HPTTL', dbkey, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hpttl pttl_fields

    # Removes expiration from one or more hash fields.
    # @note Requires Redis 7.4+
    #
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of results for each field:
    #   -2 if field does not exist, -1 if field has no expiration,
    #   1 if expiration was removed
    #
    # @example Remove expiration from fields
    #   my_hash.persist_fields('important_data')  #=> [1]
    def persist_fields(*fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HPERSIST', dbkey, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hpersist persist_fields

    # Returns the absolute Unix expiration timestamp in seconds for hash fields.
    # @note Requires Redis 7.4+
    #
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of timestamps for each field:
    #   -2 if field does not exist, -1 if field has no expiration,
    #   otherwise the absolute Unix timestamp in seconds
    #
    # @example Get expiration timestamp
    #   my_hash.expiretime_fields('session')  #=> [1700000000]
    def expiretime_fields(*fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HEXPIRETIME', dbkey, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hexpiretime expiretime_fields

    # Returns the absolute Unix expiration timestamp in milliseconds for hash fields.
    # @note Requires Redis 7.4+
    #
    # @param fields [Array<String>] One or more field names
    # @return [Array<Integer>] Array of timestamps in milliseconds
    #
    # @example Get precise expiration timestamp
    #   my_hash.pexpiretime_fields('session')  #=> [1700000000000]
    def pexpiretime_fields(*fields)
      string_fields = fields.flatten.compact.map(&:to_s)
      dbclient.call('HPEXPIRETIME', dbkey, 'FIELDS', string_fields.size, *string_fields)
    end
    alias hpexpiretime pexpiretime_fields

    # The Great Database Refresh-o-matic 3000 for HashKey!
    #
    # This method performs a complete refresh of the hash's state from the database.
    # It's like giving your hash a memory transfusion - out with the old state,
    # in with the fresh data straight from Valkey/Redis!
    #
    # @note This operation is atomic - it either succeeds completely or fails
    #   safely. Any unsaved changes to the hash will be overwritten.
    #
    # @return [void] Returns nothing, but your hash will be sparkling clean
    #   with all its fields synchronized with the database.
    #
    # @raise [Familia::KeyNotFoundError] If the dbkey for this hash no
    #   longer exists. Time travelers beware!
    #
    # @example Basic usage
    #   my_hash.refresh!  # ZAP! Fresh data loaded
    #
    # @example With error handling
    #   begin
    #     my_hash.refresh!
    #   rescue Familia::KeyNotFoundError
    #     puts "Oops! Our hash seems to have vanished into the Database void!"
    #   end
    def refresh!
      Familia.trace :REFRESH, nil, self.class.uri if Familia.debug?
      raise Familia::KeyNotFoundError, dbkey unless dbclient.exists(dbkey)

      fields = hgetall
      Familia.debug "[refresh!] #{self.class} #{dbkey} #{fields.keys}"

      # For HashKey, we update by merging the fresh data
      update(fields)
    end

    # The friendly neighborhood refresh method!
    #
    # This method is like refresh! but with better manners - it returns self
    # so you can chain it with other methods. It's perfect for when you want
    # to refresh your hash and immediately do something with it.
    #
    # @return [self] Returns the refreshed hash, ready for more adventures!
    #
    # @raise [Familia::KeyNotFoundError] If the dbkey does not exist.
    #   The hash must exist in Valkey/Redis-land for this to work!
    #
    # @example Refresh and chain
    #   my_hash.refresh.keys  # Refresh and get all keys
    #   my_hash.refresh['field']  # Refresh and get a specific field
    #
    # @see #refresh! For the heavy lifting behind the scenes
    def refresh
      refresh!
      self
    end

    Familia::DataType.register self, :hash
    Familia::DataType.register self, :hashkey
  end
end
