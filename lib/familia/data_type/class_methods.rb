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

      def relations?
        @has_related_fields ||= false
      end
    end
  end
end
