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

        # Strings are already strings in Redis - no need to JSON-encode them
        # This avoids double-quoting and simplifies storage
        return val.to_s if val.is_a?(String)

        # All non-string values use JSON serialization for type preservation
        # (Integer, Boolean, Float, nil, Hash, Array)
        Familia::JsonSerializer.dump(val)
      end

      # Converts a Database string value back to its original Ruby type
      #
      # This method attempts to deserialize JSON strings back to their original
      # Hash or Array types. Simple string values are returned as-is.
      #
      # DESIGN NOTE: Type Preservation vs Performance
      # ----------------------------------------------
      # Git History:
      # - 32c3702 (2025-05-28): Original implementation with complex-type-only return
      #   "Only return parsed value if it's a complex type (Hash/Array)"
      #   Rationale: Prevent unwanted type coercion ("123" → 123, "true" → true)
      #
      # - 6680fdc (2025-05-28): Paired with serialize_value refinement
      #   "only attempt JSON serialization for Array and Hash types"
      #   Establishes contract: serialize only encodes complex types as JSON
      #
      # - acbe28f (2025-10-02): File reorganization, check still present
      #   Complex-type check maintained: "return parsed if parsed.is_a?(Hash/Array)"
      #
      # Current Implementation:
      # Maintains the original complex-type-only approach for safety. While this means
      # we parse JSON but discard simple-type results, it prevents type coercion bugs.
      # The paired serialize_value() contract ensures:
      # 1. Strings stored as-is (no JSON encoding)
      # 2. All other types JSON-encoded (Integer, Boolean, Float, nil, Hash, Array)
      #
      # Therefore, any value that successfully parses as JSON SHOULD be Hash/Array.
      # The type check is defensive - catching cases where simple values were
      # accidentally JSON-encoded upstream
      #
      # @param val [String] The string value from Redis to deserialize
      # @param symbolize [Boolean] Whether to symbolize hash keys (default: true)
      # @return [Object] The deserialized value (Hash, Array, or original string)
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

      private

      # Check if a hash looks like encrypted field data
      # Encrypted data has specific keys: algorithm, nonce, ciphertext, auth_tag, key_version
      def encrypted_field_data?(hash)
        required_keys = %w[algorithm nonce ciphertext auth_tag key_version]
        required_keys.all? { |key| hash.key?(key) || hash.key?(key.to_sym) }
      end
    end
  end
end
