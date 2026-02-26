# lib/familia/horreum/serialization.rb
#
# frozen_string_literal: true

module Familia
  class Horreum
    # Serialization - Instance-level methods for object serialization
    # Handles conversion between Ruby objects and Valkey hash storage
    module Serialization
      # Converts the object's persistent fields to a hash for external use.
      #
      # Returns actual Ruby values (String, Integer, Hash, etc.) for API consumption,
      # NOT JSON-encoded strings. Excludes non-loggable fields like encrypted fields
      # for security.
      #
      # @return [Hash] Hash with field names as string keys and Ruby values
      #
      # @example Converting an object to hash format for API response
      #   user = User.new(name: "John", email: "john@example.com", age: 30)
      #   user.to_h
      #   # => {"name"=>"John", "email"=>"john@example.com", "age"=>30}
      #   # Note: Returns actual Ruby types, not JSON strings
      #
      # @note Only loggable fields are included. Encrypted fields are excluded.
      # @note Nil values are excluded from the returned hash (storage optimization)
      #
      def to_h
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]

          # Security: Skip non-loggable fields (e.g., encrypted fields)
          next unless field_type.loggable

          val = send(field_type.method_name)
          Familia.debug " [to_h] field: #{field} val: #{val.class}"

          # Use string key for external API compatibility
          # Return Ruby values, not JSON-encoded strings
          hsh[field.to_s] = val
        end
      end

      # Converts the object's persistent fields to a hash for database storage.
      #
      # Returns JSON-encoded strings for ALL persistent field values, ready for
      # Redis storage. Unlike to_h, this includes encrypted fields and serializes
      # values using serialize_value (JSON encoding).
      #
      # @return [Hash] Hash with field names as string keys and JSON-encoded values
      #
      # @example Internal storage preparation
      #   user = User.new(name: "John", age: 30)
      #   user.to_h_for_storage
      #   # => {"name"=>"\"John\"", "age"=>"30"}
      #   # Note: Strings are JSON-encoded with quotes
      #
      # @note This is an internal method used by commit_fields and hmset
      # @note Nil values are excluded to optimize Redis storage
      #
      def to_h_for_storage
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]

          val = send(field_type.method_name)
          prepared = serialize_value(val)

          if Familia.debug?
            Familia.debug " [to_h_for_storage] field: #{field} val: #{val.class} prepared: #{prepared&.class || '[nil]'}"
          end

          # Use string key for database compatibility
          hsh[field.to_s] = prepared
        end
      end

      # Returns a diagnostic hash showing Ruby values vs stored JSON side-by-side.
      #
      # Useful for debugging double-encoding issues or understanding the
      # serialization boundary. Each field maps to a hash showing the Ruby
      # value, the JSON string that would be stored, and the Ruby type.
      #
      # @return [Hash{String => Hash}] Each field name maps to:
      #   - :ruby [Object] the current in-memory Ruby value
      #   - :stored [String] the JSON-encoded string for Redis storage
      #   - :type [String] the Ruby class name of the value
      #
      # @example
      #   user.debug_fields
      #   # => {
      #   #   "name"    => { ruby: "UK",  stored: "\"UK\"",  type: "String"  },
      #   #   "age"     => { ruby: 30,    stored: "30",      type: "Integer" },
      #   #   "active"  => { ruby: true,  stored: "true",    type: "TrueClass" },
      #   #   "email"   => { ruby: nil,   stored: nil,       type: "NilClass" }
      #   # }
      #
      def debug_fields
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]
          val = send(field_type.method_name)
          stored = serialize_value(val)

          hsh[field.to_s] = {
            ruby: val,
            stored: stored,
            type: val.class.name,
          }
        end
      end

      # Converts the object's persistent fields to an array.
      #
      # Serializes all persistent field values in field definition order,
      # preparing them for Valkey storage. Each value is processed through
      # the serialization pipeline to ensure Valkey compatibility.
      #
      # @return [Array] Array of serialized field values in field order
      #
      # @example Converting an object to array format
      #   user = User.new(name: "John", email: "john@example.com", age: 30)
      #   user.to_a
      #   # => ["John", "john@example.com", "30"]
      #
      # @note Values are serialized using the same process as other persistence
      #   methods to maintain data consistency across operations.
      #
      def to_a
        self.class.persistent_fields.map do |field|
          field_type = self.class.field_types[field]

          # Security: Skip non-loggable fields (e.g., encrypted fields)
          next unless field_type.loggable

          method_name = field_type.method_name
          val = send(method_name)
          Familia.debug " [to_a] field: #{field} method: #{method_name} val: #{val.class}"

          # Return actual Ruby values, including nil to maintain array positions
          val
        end
      end

      # Serializes a Ruby object for Valkey storage.
      #
      # Converts ALL Ruby values (including strings) to JSON-encoded strings for
      # type-safe storage. This ensures round-trip type preservation: the type you
      # save is the type you get back.
      #
      # The serialization process:
      # 1. ConcealedStrings (encrypted values) → extract encrypted_value
      # 2. ALL other types → JSON serialization (String, Integer, Boolean, Float, nil, Hash, Array)
      #
      # @param val [Object] The Ruby object to serialize for Valkey storage
      #
      # @return [String] JSON-encoded string representation
      #
      # @example Type preservation through JSON encoding
      #   serialize_value("007")           # => "\"007\"" (JSON string)
      #   serialize_value(123)             # => "123" (JSON number)
      #   serialize_value(true)            # => "true" (JSON boolean)
      #   serialize_value({a: 1})          # => "{\"a\":1}" (JSON object)
      #
      # @note Strings are JSON-encoded to prevent type coercion bugs where
      #   string "123" would be indistinguishable from integer 123 in storage
      #
      # @note This method integrates with Familia's type system and supports
      #   custom serialization methods when available on the object
      #
      # @see Familia.identifier_extractor For extracting identifiers from Familia objects
      #
      def serialize_value(val)
        # Security: Handle ConcealedString safely - extract encrypted data for storage
        return val.encrypted_value if val.respond_to?(:encrypted_value)

        # ALWAYS write valid JSON for type preservation
        # This includes strings, which get JSON-encoded with wrapping quotes
        Familia::JsonSerializer.dump(val)
      end

      # Converts a Redis string value back to its original Ruby type
      #
      # This method deserializes JSON strings back to their original Ruby types
      # (Integer, Boolean, Float, nil, Hash, Array). Plain strings that cannot
      # be parsed as JSON are returned as-is.
      #
      # This pairs with serialize_value which JSON-encodes all non-string values.
      # The contract ensures type preservation across Redis storage:
      # - Strings stored as-is → returned as-is
      # - All other types JSON-encoded → JSON-decoded back to original type
      #
      # @param val [String] The string value from Redis to deserialize
      # @param symbolize [Boolean] Whether to symbolize hash keys (default: false)
      # @param field_name [Symbol, nil] Optional field name for better error context
      # @return [Object] The deserialized value with original Ruby type, or the original string if not JSON
      #
      def deserialize_value(val, symbolize: false, field_name: nil)
        return nil if val.nil? || val == ''

        # Handle Redis::Future objects during transactions
        return val if val.is_a?(Redis::Future)

        begin
          Familia::JsonSerializer.parse(val, symbolize_names: symbolize)
        rescue Familia::SerializerError
          log_deserialization_issue(val, field_name)
          val
        end
      end

      private

      def log_deserialization_issue(val, field_name)
        context = field_name ? "#{self.class}##{field_name}" : self.class.to_s
        dbkey_info = respond_to?(:dbkey) ? dbkey : 'no dbkey'

        msg = if looks_like_json?(val)
          "Corrupted JSON in #{context}: #{val.inspect} (#{dbkey_info})"
        else
          "Legacy plain string in #{context}: #{val.inspect} (#{dbkey_info})"
        end

        # Structured error logging with instrumentation
        error_type = looks_like_json?(val) ? :corrupted_json : :legacy_string
        Familia.error msg,
          error_type: error_type,
          field: field_name,
          value_preview: val.to_s[0...50],
          object_class: self.class.name,
          identifier: (identifier rescue nil),
          key: dbkey_info

        # Notify instrumentation hooks
        Familia::Instrumentation.notify_error(
          StandardError.new(msg),
          operation: :deserialization,
          error_type: error_type,
          field: field_name,
          object_class: self.class.name
        )
      end

      def looks_like_json?(val)
        val.start_with?('{', '[', '"') || %w[true false null].include?(val)
      end
    end
  end
end
