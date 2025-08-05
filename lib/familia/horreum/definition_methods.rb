# lib/familia/horreum/definition_methods.rb

require_relative 'related_fields_management'

module Familia
  class Horreum
    # Class-level instance variables
    # These are set up as nil initially and populated later
    @dbclient = nil # TODO
    @identifier_field = nil
    @default_expiration = nil
    @logical_database = nil
    @uri = nil
    @suffix = nil
    @prefix = nil
    @fields = nil # []
    @class_related_fields = nil # {}
    @related_fields = nil # {}
    @dump_method = nil
    @load_method = nil

    # DefinitionMethods: Provides class-level functionality for Horreum
    #
    # This module is extended into classes that include Familia::Horreum,
    # providing methods for Database operations and object management.
    #
    # Key features:
    # * Includes RelatedFieldsManagement for DataType field handling
    # * Defines methods for managing fields, identifiers, and dbkeys
    # * Provides utility methods for working with Database objects
    #
    module DefinitionMethods
      include Familia::Settings
      include Familia::Horreum::RelatedFieldsManagement

      # Sets or retrieves the unique identifier field for the class.
      #
      # This method defines or returns the field or method that contains the unique
      # identifier used to generate the dbkey for the object. If a value is provided,
      # it sets the identifier field; otherwise, it returns the current identifier field.
      #
      # @param [Object] val the field name or method to set as the identifier field (optional).
      # @return [Object] the current identifier field.
      #
      def identifier_field(val = nil)
        if val
          # Validate identifier field definition at class definition time
          case val
          when Symbol, String, Proc
            @identifier_field = val
          else
            raise Problem, <<~ERROR
              Invalid identifier field definition: #{val.inspect}.
              Use a field name (Symbol/String) or Proc.
            ERROR
          end
        end
        @identifier_field
      end

      # Defines a field for the class and creates accessor methods.
      #
      # This method defines a new field for the class, creating getter and setter
      # instance methods similar to `attr_accessor`. It also generates a fast
      # writer method for immediate persistence to Redis.
      #
      # @param [Symbol, String] name the name of the field to define. If a method
      # with the same name already exists, an error is raised.
      #
      def field(name,
                as: name,
                fast_method: :"#{name}!")
        fields << name


        define_regular_attribute(name)
        define_fast_attribute(name, fast_method)
      end

      def suffix(a = nil, &blk)
        @suffix = a || blk if a || !blk.nil?
        @suffix || Familia.default_suffix
      end

      # Sets or retrieves the prefix for generating Redis keys.
      #
      # @param a [String, Symbol, nil] the prefix to set (optional).
      # @return [String, Symbol] the current prefix.
      #
      # The exception is only raised when both @prefix is nil/falsy AND name is nil,
      # which typically occurs with anonymous classes that haven't had their prefix
      # explicitly set.
      #
      def prefix(a = nil)
        @prefix = a if a
        @prefix || begin
          if name.nil?
            raise Problem, 'Cannot generate prefix for anonymous class. ' \
                           'Use `prefix` method to set explicitly.'
          end
          name.downcase.gsub('::', Familia.delim).to_sym
        end
      end

      def logical_database(v = nil)
        Familia.trace :DB, Familia.dbclient, "#{@logical_database} #{v}", caller(1..1) if Familia.debug?
        @logical_database = v unless v.nil?
        @logical_database || parent&.logical_database
      end

      # Returns the list of field names defined for the class in the order
      # that they were defined. i.e. `field :a; field :b; fields => [:a, :b]`.
      def fields
        @fields ||= []
        @fields
      end

      def class_related_fields
        @class_related_fields ||= {}
        @class_related_fields
      end

      def related_fields
        @related_fields ||= {}
        @related_fields
      end

      def has_relations?
        @has_relations ||= false
      end

      # Converts the class name into a string that can be used to look up
      # configuration values. This is particularly useful when mapping
      # familia models with specific database numbers in the configuration.
      #
      # @example V2::Session.config_name => 'session'
      #
      # @return [String] The underscored class name as a string
      def config_name
        name.split('::').last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
      end

      def dump_method
        @dump_method || :to_json # Familia.dump_method
      end

      def load_method
        @load_method || :from_json # Familia.load_method
      end

      private

      def define_regular_attribute(name)
        if method_defined?(name)
          raise ArgumentError, "Method #{name} already defined for #{self}"
        end

        attr_accessor name
      end

      # Defines a fast attribute method with a bang (!) suffix for a given
      # attribute name. Fast attribute methods are used to immediately read or
      # write attribute values from/to the database. Calling a fast attribute
      # method has no effect on any of the object's other attributes and does
      # not trigger a call to update the object's expiration time.
      #
      # @param [Symbol, String] name the name of the attribute for which the
      #   fast method is defined.
      # @return [Object] the current value of the attribute when called without
      #   arguments.
      # @raise [ArgumentError] if more than one argument is provided.
      # @raise [RuntimeError] if an exception occurs during the execution of the
      #   method.
      #
      def define_fast_attribute(name, method_name = nil)
        method_name ||= :"#{name}!"
        raise ArgumentError, 'Must end with !' unless method_name.to_s.end_with?('!')
        raise ArgumentError, "#{self}##{method_name} exists" if method_defined?(:"#{method_name}")

        # Fast attribute accessor method for the '#{name}' attribute.
        # This method provides immediate read and write access to the attribute
        # in Redis.
        #
        # When called without arguments, it retrieves the current value of the
        # attribute from Redis.
        # When called with an argument, it immediately persists the new value to
        # Redis.
        #
        # @overload #{method_name}
        #   Retrieves the current value of the attribute from Redis.
        #   @return [Object] the current value of the attribute.
        #
        # @overload #{method_name}(value)
        #   Sets and immediately persists the new value of the attribute to
        #   Redis.
        #   @param value [Object] the new value to set for the attribute.
        #   @return [Object] the newly set value.
        #
        # @raise [ArgumentError] if more than one argument is provided.
        # @raise [RuntimeError] if an exception occurs during the execution of
        #   the method.
        #
        # @note This method bypasses any object-level caching and interacts
        #   directly with Redis. It does not trigger updates to other attributes
        #   or the object's expiration time.
        #
        # @example
        #
        #      def field_name!(*args)
        #        # Method implementation
        #      end
        #
        define_method method_name do |*args|
          # Check if the correct number of arguments is provided (exactly one).
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0 or 1)" if args.size > 1

          val = args.first

          # If no value is provided to this fast attribute method, make a call
          # to the db to return the current stored value of the hash field.
          return hget name if val.nil?

          begin
            # Trace the operation if debugging is enabled.
            Familia.trace :FAST_WRITER, dbclient, "#{name}: #{val.inspect}", caller(1..1) if Familia.debug?

            # Convert the provided value to a format suitable for Database storage.
            prepared = serialize_value(val)
            Familia.ld "[.define_fast_attribute] #{method_name} val: #{val.class} prepared: #{prepared.class}"

            # Use the existing accessor method to set the attribute value.
            send :"#{name}=", val

            # Persist the value to Database immediately using the hset command.
            hset name, prepared
          rescue Familia::Problem => e
            # Raise a custom error message if an exception occurs during the execution of the method.
            raise "#{method_name} method failed: #{e.message}", e.backtrace
          end
        end
      end

    end
  end
end
