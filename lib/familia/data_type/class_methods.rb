# lib/familia/data_type/class_methods.rb
#
# frozen_string_literal: true

module Familia
  class DataType
    # ClassMethods - Class-level DSL methods for defining DataType behavior
    #
    # This module is extended into classes that inherit from Familia::DataType,
    # providing class methods for type registration, configuration, and inheritance.
    #
    # Key features:
    # * Type registration system for creating DataType subclasses
    # * Database and connection configuration
    # * Inheritance hooks for propagating settings
    # * Option validation and filtering
    #
    module ClassMethods
      attr_accessor :parent, :suffix, :prefix, :uri
      attr_writer :logical_database

      # To be called inside every class that inherits DataType
      # +methname+ is the term used for the class and instance methods
      # that are created for the given +klass+ (e.g. set, list, etc)
      def register(klass, methname)
        Familia.trace :REGISTER, nil, "[#{self}] Registering #{klass} as #{methname.inspect}" if Familia.debug?

        @registered_types[methname] = klass
      end

      # Get the registered type class from a given method name
      # +methname+ is the method name used to register the class (e.g. :set, :list, etc)
      # Returns the registered class or nil if not found
      def registered_type(methname)
        @registered_types[methname]
      end

      def logical_database(val = nil)
        @logical_database = val unless val.nil?
        @logical_database || parent&.logical_database
      end

      def uri(val = nil)
        @uri = val unless val.nil?
        @uri || (parent ? parent.uri : Familia.uri)
      end

      def inherited(obj)
        Familia.trace :DATATYPE, nil, "#{obj} is my kinda type" if Familia.debug?
        obj.logical_database = logical_database
        obj.default_expiration = default_expiration # method added via Features::Expiration
        obj.uri = uri
        super
      end

      def valid_keys_only(opts)
        opts.slice(*DataType.valid_options)
      end

      # Validates a +max_length:+ option against the DataType class that
      # would receive it. Class-level so a caller holding only a definition
      # (Horreum.configure_related_field) can fail at configuration time with
      # exactly the error #initialize would raise at first use.
      #
      # @param value [Object, nil] the proposed cap
      # @param klass [Class] the DataType subclass the cap is for
      # @raise [ArgumentError] if value is present and not a positive Integer,
      #   or if klass does not implement max_length trimming
      def validate_max_length!(value, klass)
        return if value.nil?

        unless value.is_a?(Integer) && value.positive?
          raise ArgumentError,
                "max_length must be a positive Integer, got #{value.inspect}"
        end

        return if klass.supports_max_length?

        raise ArgumentError,
              "max_length is not supported by #{klass.name} " \
              '(only SortedSet and ListKey trim on write)'
      end

      # @param mode [Symbol, nil] a +dirty_write_warnings:+ option value
      # @raise [ArgumentError] if mode is present and not a recognized mode
      def validate_dirty_write_warnings!(mode)
        return if mode.nil? || DIRTY_WRITE_MODES.include?(mode)

        raise ArgumentError,
              "dirty_write_warnings must be one of #{DIRTY_WRITE_MODES.inspect}, got #{mode.inspect}"
      end

      def relations?
        @has_related_fields ||= false
      end
    end
  end
end
