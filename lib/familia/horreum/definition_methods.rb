# lib/familia/horreum/definition_methods.rb

require_relative 'related_fields_management'

module Familia
  VALID_STRATEGIES = %i[raise skip warn overwrite].freeze

  # Data class to hold field definition details
  #
  # This class encapsulates all the information about a field definition,
  # including the field name, method names, and conflict resolution strategy.
  #
  FieldDefinition = Data.define(:field_name, :method_name, :fast_method_name, :on_conflict, :category) do
    def initialize(field_name:, method_name:, fast_method_name:, on_conflict:, category:)
      super(
        field_name: field_name,
        method_name: method_name,
        fast_method_name: fast_method_name,
        on_conflict: on_conflict,
        category: category || :field
      )
    end

    # Returns all method names generated for this field
    def generated_methods
      [method_name, fast_method_name]
    end

    def to_s
      attributes = format_attributes
      "#<#{self.class.name} #{attributes.join(' ')}>"
    end
    alias inspect to_s

    # Helper for serialization filtering
    def persistent?
      category != :transient
    end

    private

    def format_attributes
      [
        "field_name=#{field_name}",
        "method_name=#{method_name}",
        "fast_method_name=#{fast_method_name}",
        "on_conflict=#{on_conflict}",
        "category=#{category}"
      ]
    end
  end

  # Familia::Horreum
  #
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
      # @param name [Symbol, String] the name of the field to define. If a method
      #   with the same name already exists, an error is raised.
      # @param as [Symbol, String, false, nil] as the name to use for the accessor method (defaults to name).
      #   If false or nil, no accessor methods are created.
      # @param fast_method [Symbol, false, nil] the name to use for the fast writer method (defaults to :"#{name}!").
      #   If false or nil, no fast writer method is created.
      # @param on_conflict [Symbol] conflict resolution strategy when method already exists:
      #   - :raise - raise error if method exists (default)
      #   - :skip - skip definition if method exists
      #   - :warn - warn but proceed (may overwrite)
      #   - :ignore - proceed silently (may overwrite)
      # @param category [Symbol, nil] field category for special handling:
      #   - nil - regular field (default)
      #   - :encrypted - field contains encrypted data
      #   - :transient - field is not persisted
      #   - Others, depending on features available
      #
      def field(name, as: name, fast_method: :"#{name}!", on_conflict: :raise, category: nil)
        fields << name

        define_attr_accessor_methods(name, as, on_conflict) if as
        define_fast_writer_method(name, as, fast_method, on_conflict) if fast_method

        # Create field definition object
        field_def = FieldDefinition.new(
          field_name: name,
          method_name: as,
          fast_method_name: fast_method,
          on_conflict: on_conflict,
          category: category,
        )

        # Track field definitions after defining field methods
        @field_definitions ||= {}
        @field_definitions[name] = field_def
      end

      # Sets or retrieves the suffix for generating Redis keys.
      #
      # @param a [String, Symbol, nil] the suffix to set (optional).
      # @param blk [Proc] a block that returns the suffix (optional).
      # @return [String, Symbol] the current suffix or Familia.default_suffix if none is set.
      #
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
        Familia.trace :DB, Familia.dbclient, "#{@logical_database} #{v.nil?}", caller(0..2) if Familia.debug?
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

      def field_definitions
        @field_definitions ||= {}
      end

      # Returns a hash mapping field names to method names for backward compatibility
      def field_method_map
        field_definitions.transform_values(&:method_name)
      end

      # Get fields for serialization (excludes transients)
      def persistent_fields
        fields.select do |field|
          field_definitions[field].persistent?
        end
      end

      private

      # Hook to detect silent overwrites and handle conflicts
      def method_added(method_name)
        super

        # Find the field definition that generated this method
        field_def = field_definitions.values.find { |fd| fd.generated_methods.include?(method_name) }
        return unless field_def

        case field_def.on_conflict
        when :warn
          warn <<~WARNING

            WARNING: Method >>> #{method_name} <<< was redefined after field definition.
            Field functionality may be broken. Consider using a different name
            with field(:field_name, as: :other_name)

            Called from:
            #{Familia.pretty_stack(limit: 3)}

          WARNING
        when :raise
          raise ArgumentError, "Method >>> #{method_name} <<< already defined for #{self}"
        when :skip
          # Do nothing, skip silently
        end
      end

      def define_attr_accessor_methods(field_name, method_name, on_conflict)
        handle_method_conflict(method_name, on_conflict) do
          # Equivalent to `attr_reader :field_name`
          define_method method_name do
            instance_variable_get(:"@#{field_name}")
          end
          # Equivalent to `attr_writer :field_name=`
          define_method :"#{method_name}=" do |value|
            instance_variable_set(:"@#{field_name}", value)
          end
        end
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
      def define_fast_writer_method(field_name, method_name, fast_method_name, on_conflict)
        raise ArgumentError, 'Must end with !' unless fast_method_name.to_s.end_with?('!')

        handle_method_conflict(fast_method_name, on_conflict) do
          # Fast attribute accessor method for the '#{field_name}' attribute.
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
          define_method fast_method_name do |*args|
            # Check if the correct number of arguments is provided (exactly one).
            raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0 or 1)" if args.size > 1

            val = args.first

            # If no value is provided to this fast attribute method, make a call
            # to the db to return the current stored value of the hash field.
            return hget field_name if val.nil?

            begin
              # Trace the operation if debugging is enabled.
              Familia.trace :FAST_WRITER, dbclient, "#{field_name}: #{val.inspect}", caller(1..1) if Familia.debug?

              # Convert the provided value to a format suitable for Database storage.
              prepared = serialize_value(val)
              Familia.ld "[.define_fast_writer_method] #{fast_method_name} val: #{val.class} prepared: #{prepared.class}"

              # Use the existing accessor method to set the attribute value.
              send :"#{method_name}=", val

              # Persist the value to Database immediately using the hset command.
              ret = hset field_name, prepared
              ret.zero? || ret.positive?
            rescue Familia::Problem => e
              # Raise a custom error message if an exception occurs during the execution of the method.
              raise "#{fast_method_name} method failed: #{e.message}", e.backtrace
            end
          end
        end
      end

      # Handles method name conflicts during dynamic method definition.
      #
      # @param method_name [Symbol, String] the method to define
      # @param strategy [Symbol] conflict resolution strategy:
      #   - :raise     - raise error if method exists (default)
      #   - :skip      - skip definition if method exists
      #   - :warn      - warn but proceed (may overwrite)
      #   - :overwrite - explicitly remove existing method first
      #
      # @yield the method definition to execute
      #
      # @example
      #   handle_method_conflict(:my_method, :skip) do
      #     attr_accessor :my_method
      #   end
      #
      # @raise [ArgumentError] if strategy invalid or method exists with :raise
      #
      # @private
      def handle_method_conflict(method_name, strategy, &)
        validate_strategy!(strategy)

        if method_exists?(method_name)
          handle_existing_method(method_name, strategy, &)
        else
          yield
        end
      end

      def validate_strategy!(strategy)
        return if VALID_STRATEGIES.include?(strategy)

        raise ArgumentError, "Invalid conflict strategy: #{strategy}. " \
                             "Valid strategies: #{VALID_STRATEGIES.join(', ')}"
      end

      def method_exists?(method_name)
        method_defined?(method_name)
      end

      def handle_existing_method(method_name, strategy)
        case strategy
        when :raise
          raise_method_exists_error(method_name)
        when :skip
          # Do nothing - skip the definition
        when :warn
          warn_method_exists(method_name)
          yield
        when :overwrite
          remove_method(method_name)
          yield
        end
      end

      def raise_method_exists_error(method_name)
        location = format_method_location(method_name)
        raise ArgumentError, "Method >>> #{method_name} <<< already defined for #{self}#{location}"
      end

      def warn_method_exists(method_name)
        location = format_method_location(method_name)
        caller_info = Familia.pretty_stack(skip: 5, limit: 3)

        warn <<~WARNING

          WARNING: Method '#{method_name}' is already defined.

          Class: #{self}#{location}

          Called from:
          #{caller_info}

        WARNING
      end

      def format_method_location(method_name)
        method_obj = instance_method(method_name)
        source_location = method_obj.source_location

        return "" unless source_location

        path = Familia.pretty_path(source_location[0])
        line = source_location[1]
        " (defined at #{path}:#{line})"
      end
    end
  end
end
