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
      # Only non-nil values are included in the resulting hash.
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
      # @note Only fields with non-nil values are included
      #
      def to_h
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]

          # Security: Skip non-loggable fields (e.g., encrypted fields)
          next unless field_type.loggable

          method_name = field_type.method_name
          val = send(method_name)
          prepared = serialize_value(val)
          Familia.ld " [to_h] field: #{field} val: #{val.class} prepared: #{prepared&.class || '[nil]'}"

          # Only include non-nil values in the hash for Valkey
          # Use string key for database compatibility
          hsh[field.to_s] = prepared unless prepared.nil?
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
      # @note Only fields with non-nil values are included for storage efficiency
      #
      def to_h_for_storage
        self.class.persistent_fields.each_with_object({}) do |field, hsh|
          field_type = self.class.field_types[field]
          method_name = field_type.method_name
          val = send(method_name)
          prepared = serialize_value(val)
          Familia.ld " [to_h_for_storage] field: #{field} val: #{val.class} prepared: #{prepared&.class || '[nil]'}"

          # Only include non-nil values in the hash for Valkey
          # Use string key for database compatibility
          hsh[field.to_s] = prepared unless prepared.nil?
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
        self.class.persistent_fields.filter_map do |field|
          field_type = self.class.field_types[field]

          # Security: Skip non-loggable fields (e.g., encrypted fields)
          next unless field_type.loggable

          method_name = field_type.method_name
          val = send(method_name)
          prepared = serialize_value(val)
          Familia.ld " [to_a] field: #{field} method: #{method_name} val: #{val.class} prepared: #{prepared.class}"
          prepared
        end
      end

      # Serializes a Ruby object for Valkey storage.
      #
      # Converts Ruby objects into the DB-compatible string representations using
      # the Familia distinguisher for type coercion. Falls back to JSON serialization
      # for complex types (Hash, Array) when the primary distinguisher returns nil.
      #
      # The serialization process:
      # 1. Attempts conversion using Familia.distinguisher with relaxed type checking
      # 2. For Hash/Array types that return nil, tries custom dump_method or Familia::JsonSerializer.dump
      # 3. Logs warnings when serialization fails completely
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
      # @see Familia.distinguisher The primary serialization mechanism
      #
      def serialize_value(val)
        # Security: Handle ConcealedString safely - extract encrypted data for storage
        return val.encrypted_value if val.respond_to?(:encrypted_value)

        prepared = Familia.distinguisher(val, strict_values: false)

        # If the distinguisher returns nil, try using the dump_method but only
        # use JSON serialization for complex types that need it.
        if prepared.nil? && (val.is_a?(Hash) || val.is_a?(Array))
          prepared = val.respond_to?(dump_method) ? val.send(dump_method) : Familia::JsonSerializer.dump(val)
        end

        # If both the distinguisher and dump_method return nil, log an error
        Familia.ld "[#{self.class}#serialize_value] nil returned for #{self.class}" if prepared.nil?

        prepared
      end

      # Converts a Database string value back to its original Ruby type
      #
      # This method attempts to deserialize JSON strings back to their original
      # Hash or Array types. Simple string values are returned as-is.
      #
      # @param val [String] The string value from Database to deserialize
      # @param symbolize [Boolean] Whether to symbolize hash keys (default: true for compatibility)
      # @return [Object] The deserialized value (Hash, Array, or original string)
      #
      def deserialize_value(val, symbolize: true)
        return val if val.nil? || val == ''

        # Try to parse as JSON first for complex types
        begin
          parsed = Familia::JsonSerializer.parse(val, symbolize_names: symbolize)
          # Only return parsed value if it's a complex type (Hash/Array)
          # Simple values should remain as strings
          return parsed if parsed.is_a?(Hash) || parsed.is_a?(Array)
        rescue Familia::SerializerError
          # Not valid JSON, return as-is
        end

        val
      end
    end
  end
end
