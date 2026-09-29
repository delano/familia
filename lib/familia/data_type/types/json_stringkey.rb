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
      Familia.transform_reply(to_s) { |str| str&.size || 0 }
    end
    alias size char_count
    alias length char_count

    # Returns the current value stored at the key.
    #
    # If a default option was provided during initialization, the default
    # is set via SETNX (set if not exists) before retrieval.
    #
    # @return [Object, Redis::Future] the deserialized value, or the default
    #   if not set. Inside a transaction or pipeline, the GET Future (resolves
    #   to the raw JSON).
    #
    def value
      echo :value, Familia.pretty_stack(limit: 1) if Familia.debug
      if @opts.key?(:default)
        was_set = dbclient.setnx(dbkey, serialize_value(@opts[:default]))
        update_expiration_if_written(was_set)
      end
      deserialize_value dbclient.get(dbkey)
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

    # Sets the value only if the key does not already exist.
    #
    # @param val [Object] the value to store
    # @return [Boolean, Redis::Future] true if the key was set, false if it
    #   already existed. Inside a transaction or pipeline, the SETNX Future
    #   of that Boolean (the Future itself is always truthy).
    #
    def setnx(val)
      warn_if_dirty!
      ret = dbclient.setnx(dbkey, serialize_value(val))
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
    # @return [Boolean, Redis::Future] true if the value is nil. Inside a
    #   transaction or pipeline, the GET Future (resolves to the raw JSON).
    #
    def empty?
      Familia.transform_reply(value, &:nil?)
    end

    # Returns the string representation of the deserialized value.
    #
    # @return [String, nil, Redis::Future] the deserialized value converted
    #   to string, or nil. Inside a transaction or pipeline, the GET Future
    #   (resolves to the raw JSON).
    #
    def to_s
      read_converted(&:to_s)
    end

    # Returns the integer representation of the deserialized value.
    #
    # @return [Integer, nil, Redis::Future] the deserialized value converted
    #   to integer, or nil. Inside a transaction or pipeline, the GET Future.
    #
    def to_i
      read_converted(&:to_i)
    end

    # Returns the float representation of the deserialized value.
    #
    # @return [Float, nil, Redis::Future] the deserialized value converted to
    #   float, or nil. Inside a transaction or pipeline, the GET Future.
    #
    def to_f
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
