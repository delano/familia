# lib/familia/data_type/serialization.rb
#
# frozen_string_literal: true

module Familia
  class DataType
    module Serialization
      # Serializes a value for storage in the database.
      #
      # @param val [Object] The value to be serialized.
      # @return [String] The JSON-serialized representation of the value.
      #
      # Serialization priority:
      # 1. Familia objects (Base instances or classes) → extract identifier
      # 2. All other values → JSON serialize for type preservation
      #
      # This unifies behavior with Horreum fields (Issue #190), ensuring
      # consistent type preservation across DataType and Horreum.
      #
      # @example Familia object reference
      #   serialize_value(customer_obj) #=> "customer_123" (identifier)
      #
      # @example Primitive values (JSON encoded)
      #   serialize_value(42)          #=> "42"
      #   serialize_value("hello")     #=> '"hello"'
      #   serialize_value(true)        #=> "true"
      #   serialize_value(nil)         #=> "null"
      #   serialize_value([1, 2, 3])   #=> "[1,2,3]"
      #
      def serialize_value(val)
        Familia.trace :TOREDIS, nil, "#{val}<#{val.class}|#{opts[:class]}>" if Familia.debug?

        # Priority 1: Handle Familia object references - extract identifier
        # This preserves the existing behavior for storing object references
        if val.is_a?(Familia::Base) || (val.is_a?(Class) && val.ancestors.include?(Familia::Base))
          prepared = val.is_a?(Class) ? val.name : val.identifier
          Familia.debug "  Familia object: #{val.class} => #{prepared}"
          return prepared
        end

        # Priority 2: Everything else gets JSON serialized for type preservation
        # This unifies behavior with Horreum fields (Issue #190)
        prepared = Familia::JsonSerializer.dump(val)
        Familia.debug "  JSON serialized: #{val.class} => #{prepared}"

        if Familia.debug?
          Familia.trace :TOREDIS, nil, "#{val}<#{val.class}> => #{prepared}<#{prepared.class}>"
        end

        prepared
      end

      # Deserializes multiple values from Valkey/Redis, removing nil values.
      #
      # @param values [Array<String>] The values to deserialize.
      # @return [Array<Object>] Deserialized objects, with nil values removed.
      #
      # @see #deserialize_values_with_nil
      #
      def deserialize_values(*values)
        # Avoid using compact! here. Using compact! as the last expression in the
        # method can unintentionally return nil if no changes are made, which is
        # not desirable. Instead, use compact to ensure the method returns the
        # expected value.
        deserialize_values_with_nil(*values).compact
      end

      # Deserializes multiple values from Valkey/Redis, preserving nil values.
      #
      # @param values [Array<String>] The values to deserialize.
      # @return [Array<Object, nil>] Deserialized objects, including nil values.
      #
      # @raise [Familia::Problem] If the specified class doesn't respond to from_json.
      #
      # @note This method attempts to deserialize each value using the specified
      #   class's from_json method. If deserialization fails for a value, it's
      #   replaced with nil.
      #
      def deserialize_values_with_nil(*values)
        Familia.debug "deserialize_values: (#{@opts}) #{values}"
        return [] if values.empty?

        # If a class option is specified, use class-based deserialization
        if @opts[:class]
          unless @opts[:class].respond_to?(:from_json)
            raise Familia::Problem, "No such method: #{@opts[:class]}.from_json"
          end

          values.collect! do |obj|
            next if obj.nil?

            val = @opts[:class].from_json(obj)
            Familia.debug "[#{self.class}#deserialize_values] nil returned for #{@opts[:class]}.from_json" if val.nil?

            val
          rescue StandardError => e
            Familia.info obj
            Familia.info "Parse error for #{dbkey} (from_json): #{e.message}"
            Familia.info e.backtrace
            nil
          end

          return values
        end

        # No class option: JSON deserialize each value for type preservation (Issue #190)
        values.flatten.collect do |obj|
          next if obj.nil?

          begin
            Familia::JsonSerializer.parse(obj)
          rescue Familia::SerializerError
            # Fallback for legacy data stored without JSON encoding
            obj
          end
        end
      end

      # Deserializes a single value from the database.
      #
      # @param val [String, nil] The value to deserialize.
      # @return [Object, nil] The deserialized object, the default value if
      #   val is nil, or nil if deserialization fails.
      #
      # Deserialization priority:
      # 1. Redis::Future objects → return as-is (transaction handling)
      # 2. nil values → return default option value
      # 3. Class option specified → use class-based deserialization
      # 4. No class option → JSON parse for type preservation
      #
      # This unifies behavior with Horreum fields (Issue #190), ensuring
      # consistent type preservation. Legacy data stored without JSON
      # encoding is returned as-is.
      #
      def deserialize_value(val)
        # Handle Redis::Future objects during transactions first
        return val if val.is_a?(Redis::Future)

        return @opts[:default] if val.nil?

        # If a class option is specified, use the existing class-based deserialization
        if @opts[:class]
          ret = deserialize_values val
          return ret&.first # return the object or nil
        end

        # No class option: JSON deserialize for type preservation (Issue #190)
        # This unifies behavior with Horreum fields
        begin
          Familia::JsonSerializer.parse(val)
        rescue Familia::SerializerError
          # Fallback for legacy data stored without JSON encoding
          val
        end
      end
    end
  end
end
