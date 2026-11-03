# lib/familia/data_type/types/json_stringkey.rb
#
# frozen_string_literal: true

module Familia
  # JsonStringKey - A string DataType that uses JSON serialization for type preservation.
  #
  # Unlike StringKey which uses raw string serialization (to support Redis operations
  # like INCR/DECR/APPEND), JsonStringKey uses the base DataType's JSON serialization
  # to preserve Ruby types across the Redis storage boundary.
  #
  # @example Basic usage
  #   class MyIndex < Familia::Horreum
  #     class_json_string :last_synced_at, default: 0.0
  #   end
  #
  #   MyIndex.last_synced_at = Familia.now.to_f  # Stored as JSON number
  #   MyIndex.last_synced_at  #=> 1704067200.123 (Float preserved)
  #
  # @example Type preservation
  #   json_str.value = 42        # Stored in Redis as: 42 (JSON number)
  #   json_str.value = true      # Stored in Redis as: true (JSON boolean)
  #   json_str.value = [1, 2, 3] # Stored in Redis as: [1,2,3] (JSON array)
  #
  # @note This class intentionally does NOT include increment/decrement or other
  #   raw string operations that are incompatible with JSON serialization.
  #
  # @note Performance: Each call to value, to_s, to_i, to_f makes a Redis
  #   roundtrip. If you need the value multiple times and don't expect it to
  #   change, store it in a local variable:
  #
  #   # Inefficient (3 Redis calls):
  #   puts json_str.to_s
  #   puts json_str.to_i
  #   puts json_str.to_f
  #
  #   # Efficient (1 Redis call):
  #   val = json_str.value
  #   puts val.to_s
  #   puts val.to_i
  #   puts val.to_f
  #
  class JsonStringKey < DataType
    include DataType::ScalarBase

    # Initialization hook (required by DataType contract)
    def init; end

    # Returns the number of characters in the string representation of the value.
    #
    # @return [Integer, Redis::Future] number of characters. Inside a
    #   transaction or pipeline, the GET Future (resolves to the raw JSON).
    #
    def char_count
      Familia.transform_reply(read_converted(&:to_s)) { |str| str&.size || 0 }
    end
    alias size char_count
    alias length char_count

    # Returns the current value stored at the key.
    #
    # If a default option was provided during initialization, the default
    # is set via SETNX (set if not exists) before retrieval, and the TTL is
    # refreshed only when the default was written. Inside a transaction or
    # pipeline the SETNX and the refresh are queued as one EVAL that makes
    # the same decision when it runs, so reading an existing key leaves its
    # TTL unchanged there too. That EVAL adds one Boolean reply to
    # MultiResult#results ahead of the GET reply.
    #
    # @return [Object, Redis::Future] the deserialized value, or the default
    #   if not set. Inside a transaction or pipeline, the GET Future (resolves
    #   to the raw JSON).
    #
    def value
      echo :value, Familia.pretty_stack(limit: 1) if Familia.debug
      conn = dbclient
      if @opts.key?(:default)
        default = serialize_value(@opts[:default])
        if queued_connection?(conn)
          queue_conditional_write(conn, :setnx, default) { |reply| reply == 1 }
        else
          update_expiration_if_written(conn.setnx(dbkey, default))
        end
      end
      deserialize_value conn.get(dbkey)
    end
    alias content value
    alias get value

    # Sets the value at the key.
    #
    # The value is JSON-serialized before storage, preserving its Ruby type.
    #
    # @param val [Object] the value to store
    # @return [String] "OK" on success
    #
    def value=(val)
      warn_if_dirty!
      ret = dbclient.set(dbkey, serialize_value(val))
      update_expiration
      ret
    end
    alias replace value=
    alias set value=

    # Sets the value only if the key does not already exist, and refreshes
    # the TTL only when it was set. Inside a transaction or pipeline the
    # SETNX and the refresh are queued as one EVAL that makes the same
    # decision when it runs.
    #
    # @param val [Object] the value to store
    # @return [Boolean, Redis::Future] true if the key was set, false if it
    #   already existed. Inside a transaction or pipeline, the EVAL Future,
    #   which resolves to that Boolean (the Future itself is always truthy).
    #
    def setnx(val)
      warn_if_dirty!
      conn = dbclient
      if queued_connection?(conn)
        return queue_conditional_write(conn, :setnx, serialize_value(val)) { |reply| reply == 1 }
      end

      ret = conn.setnx(dbkey, serialize_value(val))
      update_expiration_if_written(ret)
      ret
    end

    # Deletes the key from the database.
    #
    # @return [Boolean] true if the key was deleted, false if it didn't exist
    #
    def del
      ret = dbclient.del dbkey
      Familia.positive?(ret)
    end

    # Checks if the value is nil (key does not exist or has no value).
    #
    # Reads with a plain GET, like #char_count, and leaves the key and its
    # TTL untouched. A declared default stands in for a missing key, as it
    # does for #value, but unlike #value this never writes the default.
    #
    # @return [Boolean, Redis::Future] true if the value is nil. Inside a
    #   transaction or pipeline, the GET Future (resolves to the raw JSON, or
    #   nil for a missing key whether or not a default is declared).
    #
    def empty?
      Familia.transform_reply(read_converted(&:itself), &:nil?)
    end

    # Returns the string representation of the deserialized value.
    #
    # Ruby calls to_s implicitly (string interpolation, Array#join, puts) and
    # prints the object's default "#<...>" form when it returns anything but
    # a String, so it cannot hand back a Redis::Future. Use #value to get the
    # GET Future inside a block.
    #
    # @return [String, nil] the deserialized value converted to string, or
    #   nil
    # @raise [Familia::OperationModeError] inside a transaction or pipeline
    #
    def to_s
      Familia.assert_replies_available!('JsonStringKey#to_s')

      read_converted(&:to_s)
    end

    # Returns the integer representation of the deserialized value. A
    # conversion method, refused inside a block like #to_s.
    #
    # @return [Integer, nil] the deserialized value converted to integer, or
    #   nil
    # @raise [Familia::OperationModeError] inside a transaction or pipeline
    #
    def to_i
      Familia.assert_replies_available!('JsonStringKey#to_i')

      read_converted(&:to_i)
    end

    # Returns the float representation of the deserialized value. A
    # conversion method, refused inside a block like #to_s.
    #
    # @return [Float, nil] the deserialized value converted to float, or nil
    # @raise [Familia::OperationModeError] inside a transaction or pipeline
    #
    def to_f
      Familia.assert_replies_available!('JsonStringKey#to_f')

      read_converted(&:to_f)
    end

    private

    # Reads the value with GET (no default applied) and converts a non-nil
    # deserialized value with the block. Passes a Redis::Future through.
    def read_converted
      Familia.transform_reply(dbclient.get(dbkey)) do |raw|
        val = deserialize_value(raw)
        val.nil? ? nil : yield(val)
      end
    end

    Familia::DataType.register self, :json_string
    Familia::DataType.register self, :json_stringkey
    Familia::DataType.register self, :jsonkey
  end
end
