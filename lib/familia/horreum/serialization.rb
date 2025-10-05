# lib/familia/horreum/serialization.rb

module Familia
  class Horreum
    # Serialization - Instance-level methods for object serialization
    # Handles conversion between Ruby objects and Valkey hash storage
    module Serialization
      # Converts the object's persistent fields to a hash for external use.
      #
      # Serializes persistent field values for external consumption (APIs, logs),
      # excluding non-loggable fields like encrypted fields for security.
      #
      # @return [Hash] Hash with field names as keys and serialized values
      #   safe for external exposure
      #
      # @example Converting an object to hash format for API response
      #   user = User.new(name: "John", email: "john@example.com", age: 30)
      #   user.to_h
      #   # => {"name"=>"John", "email"=>"john@example.com", "age"=>"30"}
      #   # encrypted fields are excluded for security
      #
      # @note Only loggable fields are included for security
      #
      def to_h
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]

          # Security: Skip non-loggable fields (e.g., encrypted fields)
          next unless field_type.loggable

          val = send(field_type.method_name)
          Familia.ld " [to_h] field: #{field} val: #{val.class}"

          # Use string key for external API compatibility
          # Return Ruby values, not JSON-encoded strings
          hsh[field.to_s] = val
        end
      end

      # Converts the object's persistent fields to a hash for database storage.
      #
      # Serializes ALL persistent field values for database storage, including
      # encrypted fields. This is used internally by commit_fields and other
      # persistence operations.
      #
      # @return [Hash] Hash with field names as keys and serialized values
      #   ready for database storage
      #
      # @note Includes ALL persistent fields, including encrypted fields
      #
      def to_h_for_storage
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]

          val = send(field_type.method_name)
          prepared = serialize_value(val)

          if Familia.debug?
            Familia.ld " [to_h_for_storage] field: #{field} val: #{val.class} prepared: #{prepared&.class || '[nil]'}"
          end

          # Use string key for database compatibility
          hsh[field.to_s] = prepared
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
          Familia.ld " [to_a] field: #{field} method: #{method_name} val: #{val.class}"

          # Return actual Ruby values, including nil to maintain array positions
          val
        end
      end

      # Serializes a Ruby object for Valkey storage.
      #
      # Converts Ruby objects into DB-compatible string representations using
      # JSON serialization for type preservation. Strings are stored as-is to
      # avoid double-quoting.
      #
      # The serialization process:
      # 1. ConcealedStrings (encrypted values) → extract encrypted_value
      # 2. Strings → store as-is (no JSON encoding)
      # 3. All other types → JSON serialization (Integer, Boolean, Float, nil, Hash, Array)
      #
      # @param val [Object] The Ruby object to serialize for Valkey storage
      #
      # @return [String, nil] The serialized value ready for Valkey storage, or nil
      #   if serialization failed
      #
      # @example Serializing different data types
      #   serialize_value("hello")        # => "hello"
      #   serialize_value(42)             # => "42"
      #   serialize_value({name: "John"}) # => '{"name":"John"}'
      #   serialize_value([1, 2, 3])      # => "[1,2,3]"
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
      # @return [Object] The deserialized value with original Ruby type, or the original string if not JSON
      #
      def deserialize_value(val, symbolize: false)
        return val if val.nil? || val == ''

        # Try to parse as JSON - if successful, we have a typed value (Integer, Boolean, etc.)
        # If parsing fails, treat as plain string (the Redis baseline)
        begin
          Familia::JsonSerializer.parse(val, symbolize_names: symbolize)
        rescue Familia::SerializerError
          # Not valid JSON - treat as plain string
          val
        end
      end

    end
  end
end
