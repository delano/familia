# lib/familia/distinguisher.rb

module Familia
  module Distinguisher
    # This method determines the appropriate transformation to apply based on
    # the class of the input argument.
    #
    # @param [Object] value_to_distinguish The value to be processed. Keep in
    #   mind that all data is stored as a string so whatever the type
    #   of the value, it will be converted to a string.
    # @param [Boolean] strict_values Whether to enforce strict value handling.
    #   Defaults to true.
    # @return [String, nil] The processed value as a string or nil for unsupported
    #   classes.
    #
    # The method uses a case statement to handle different classes:
    # - For `Symbol`, `String`, `Integer`, and `Float` classes, it traces the
    #   operation and converts the value to a string.
    # - For `Familia::Horreum` class, it traces the operation and returns the
    #   identifier of the value.
    # - For `TrueClass`, `FalseClass`, and `NilClass`, it traces the operation and
    #   converts the value to a string ("true", "false", or "").
    # - For any other class, it traces the operation and returns nil.
    #
    # Alternative names for `value_to_distinguish` could be `input_value`, `value`,
    # or `object`.
    #
    def distinguisher(value_to_distinguish, strict_values: true)
      case value_to_distinguish
      when ::Symbol, ::String, ::Integer, ::Float
        Familia.trace :TOREDIS_DISTINGUISHER, nil, 'string' if Familia.debug?

        # Symbols and numerics are naturally serializable to strings
        # so it's a relatively low risk operation.
        value_to_distinguish.to_s

      when ::TrueClass, ::FalseClass, ::NilClass
        Familia.trace :TOREDIS_DISTINGUISHER, nil, 'true/false/nil' if Familia.debug?

        # TrueClass, FalseClass, and NilClass are considered high risk because their
        # original types cannot be reliably determined from their serialized string
        # representations. This can lead to unexpected behavior during deserialization.
        # For instance, a TrueClass value serialized as "true" might be deserialized as
        # a String, causing application errors. Even more problematic, a NilClass value
        # serialized as an empty string makes it impossible to distinguish between a
        # nil value and an empty string upon deserialization. Such scenarios can result
        # in subtle, hard-to-diagnose bugs. To mitigate these risks, we raise an
        # exception when encountering these types unless the strict_values option is
        # explicitly set to false.
        #
        raise Familia::NotDistinguishableError, value_to_distinguish if strict_values

        value_to_distinguish.to_s #=> "true", "false", ""

      when Familia::Base, Class
        Familia.trace :TOREDIS_DISTINGUISHER, nil, 'base' if Familia.debug?

        # When called with a class we simply transform it to its name. For
        # instances of Familia class, we store the identifier.
        if value_to_distinguish.is_a?(Class)
          value_to_distinguish.name
        else
          value_to_distinguish.identifier
        end

      else
        Familia.trace :TOREDIS_DISTINGUISHER, nil, "else1 #{strict_values}" if Familia.debug?

        if value_to_distinguish.class.ancestors.member?(Familia::Base)
          Familia.trace :TOREDIS_DISTINGUISHER, nil, 'isabase' if Familia.debug?

          value_to_distinguish.identifier

        else
          Familia.trace :TOREDIS_DISTINGUISHER, nil, "else2 #{strict_values}" if Familia.debug?
          raise Familia::NotDistinguishableError, value_to_distinguish if strict_values

          nil
        end
      end
    end
  end

  extend Distinguisher
end
