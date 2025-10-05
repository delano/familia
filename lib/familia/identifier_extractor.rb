# lib/familia/identifier_extractor.rb

module Familia
  # IdentifierExtractor - Extracts identifiers from Familia objects for storage
  #
  # This module provides a focused mechanism for converting object references
  # into Redis-storable strings. It handles two primary cases:
  #
  # 1. Class references: Customer → "Customer"
  # 2. Familia::Base instances: customer_obj → customer_obj.identifier
  #
  # This is primarily used by DataType serialization when storing object
  # references in Redis data structures (lists, sets, zsets). It extracts
  # the identifier rather than serializing the entire object.
  #
  # @example With class_zset
  #   class Customer < Familia::Horreum
  #     class_zset :instances, class: self
  #   end
  #   # When adding: Customer.instances.add(customer_obj)
  #   # Stores: customer_obj.identifier (e.g., "customer_123")
  #
  module IdentifierExtractor
    # Extracts a Redis-storable identifier from a Familia object or class.
    #
    # @param value [Object] The value to extract an identifier from
    # @return [String] The extracted identifier or class name
    # @raise [Familia::NotDistinguishableError] If value is not a Class or Familia::Base
    #
    def identifier_extractor(value, strict_values: true)
      case value
      when ::Symbol, ::String, ::Integer, ::Float
        Familia.trace :IDENTIFIER_EXTRACTOR, nil, 'simple_value' if Familia.debug?
        # DataTypes (lists, sets, zsets) can store simple values directly
        # Convert to string for Redis storage
        value.to_s

      when Class
        Familia.trace :IDENTIFIER_EXTRACTOR, nil, 'class' if Familia.debug?
        value.name

      when Familia::Base
        Familia.trace :IDENTIFIER_EXTRACTOR, nil, 'base_instance' if Familia.debug?
        value.identifier

      else
        # Check if value's class inherits from Familia::Base
        if value.class.ancestors.member?(Familia::Base)
          Familia.trace :IDENTIFIER_EXTRACTOR, nil, 'base_ancestor' if Familia.debug?
          value.identifier
        else
          Familia.trace :IDENTIFIER_EXTRACTOR, nil, 'error' if Familia.debug?
          raise Familia::NotDistinguishableError, value
        end
      end
    end
  end

  extend IdentifierExtractor
end
