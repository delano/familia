# lib/familia/data_type/serialization.rb

module Familia
  class DataType
    module Serialization
      # Serializes a value for storage in the database.
      #
      # @param val [Object] The value to be serialized.
      # @param strict_values [Boolean] Whether to enforce strict value
      #   serialization (default: true).
      # @return [String, nil] The serialized representation of the value, or nil
      #   if serialization fails.
      #
      # @note When a class option is specified, it uses Familia.identifier_extractor
      #   to extract the identifier from objects. Otherwise, it extracts identifiers
      #   from Familia::Base instances or class names.
      #
      # @example With a class option
      #   serialize_value(User.new(name: "Cloe"), strict_values: false) #=> '{"name":"Cloe"}'
      #
      # @example Without a class option
      #   serialize_value(123) #=> "123"
      #   serialize_value("hello") #=> "hello"
      #
      # @raise [Familia::NotDistinguishableError] If serialization fails under strict
      #   mode.
      #
      def serialize_value(val, strict_values: true)
        prepared = nil

        Familia.trace :TOREDIS, nil, "#{val}<#{val.class}|#{opts[:class]}>" if Familia.debug?

        if opts[:class]
          prepared = Familia.identifier_extractor(opts[:class])
          Familia.ld "  from opts[class] <#{opts[:class]}>: #{prepared || '<nil>'}"
        end

        if prepared.nil?
          # Enforce strict values when no class option is specified
          prepared = Familia.identifier_extractor(val)
          Familia.ld "  from <#{val.class}> => <#{prepared.class}>"
        end

        if Familia.debug?
          Familia.trace :TOREDIS, nil, "#{val}<#{val.class}|#{opts[:class]}> => #{prepared}<#{prepared.class}>"
        end

        Familia.warn "[#{self.class}#serialize_value] nil returned for #{opts[:class]}##{name}" if prepared.nil?
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
      # @raise [Familia::Problem] If the specified class doesn't respond to the
      #   load method.
      #
      # @note This method attempts to deserialize each value using the specified
      #   class's load method. If deserialization fails for a value, it's
      #   replaced with nil.
      #
      def deserialize_values_with_nil(*values)
        Familia.ld "deserialize_values: (#{@opts}) #{values}"
        return [] if values.empty?
        return values.flatten unless @opts[:class]

        unless @opts[:class].respond_to?(load_method)
          raise Familia::Problem, "No such method: #{@opts[:class]}##{load_method}"
        end

        values.collect! do |obj|
          next if obj.nil?

          val = @opts[:class].send load_method, obj
          Familia.ld "[#{self.class}#deserialize_values] nil returned for #{@opts[:class]}##{name}" if val.nil?

          val
        rescue StandardError => e
          Familia.info val
          Familia.info "Parse error for #{dbkey} (#{load_method}): #{e.message}"
          Familia.info e.backtrace
          nil
        end

        values
      end

      # Deserializes a single value from the database.
      #
      # @param val [String, nil] The value to deserialize.
      # @return [Object, nil] The deserialized object, the default value if
      #   val is nil, or nil if deserialization fails.
      #
      # @note If no class option is specified, the original value is
      #   returned unchanged.
      #
      # NOTE: Currently only the DataType class uses this method. Horreum
      # fields are a newer addition and don't support the full range of
      # deserialization options that DataType supports. It uses serialize_value
      # for serialization since everything becomes a string in Valkey.
      #
      def deserialize_value(val)
        # Handle Redis::Future objects during transactions first
        return val if val.is_a?(Redis::Future)

        return @opts[:default] if val.nil?

        return val unless @opts[:class]

        ret = deserialize_values val
        ret&.first # return the object or nil
      end
    end
  end
end
