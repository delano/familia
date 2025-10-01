# lib/familia/data_type/types/hashkey.rb

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
      Familia.le "[hset]= #{e.message}"
      Familia.ld "[hset]= #{dbkey} #{field}=#{val}" if Familia.debug
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
      Familia.le "[hsetnx] #{e.message}"
      Familia.ld "[hsetnx] #{dbkey} #{field}=#{val}" if Familia.debug
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
    alias remove remove_field # deprecated

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
      Familia.trace :REFRESH, nil, uri if Familia.debug?
      raise Familia::KeyNotFoundError, dbkey unless dbclient.exists(dbkey)

      fields = hgetall
      Familia.ld "[refresh!] #{self.class} #{dbkey} #{fields.keys}"

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
