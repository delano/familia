# lib/familia/horreum/definition.rb

require_relative 'settings'

require_relative '../field_type'

module Familia
  VALID_STRATEGIES = %i[raise skip ignore warn overwrite].freeze

  # Familia::Horreum
  #
  class Horreum
    # Class-level instance variables
    # These are set up as nil initially and populated later
    #
    # Connection and database settings
    @dbclient = nil
    @logical_database = nil
    @uri = nil

    # Database Key generation settings
    @prefix = nil
    @identifier_field = nil
    @suffix = nil

    # Fields and relationships
    @fields = nil
    @class_related_fields = nil
    @related_fields = nil
    @default_expiration = nil

    # Field groups
    @field_groups = nil
    @current_field_group = nil

    # DefinitionMethods - Class-level DSL methods for defining Horreum model structure
    #
    # This module is extended into classes that include Familia::Horreum,
    # providing class methods for defining model structure and configuration
    # (e.g., Customer.field :name, Customer.identifier_field :custid).
    #
    # Key features:
    # * Defines DSL methods for field definitions (field, identifier_field)
    # * Includes RelatedFieldsManagement for DataType field DSL (list, set, zset, etc.)
    # * Provides class-level configuration (prefix, suffix, logical_database)
    # * Manages field metadata and inheritance
    #
    module DefinitionMethods
      include Familia::Settings
      include Familia::Horreum::RelatedFieldsManagement # Provides DataType field methods

      # Defines a field group to organize related fields.
      #
      # Field groups provide a way to categorize and query fields by purpose or feature.
      # When a block is provided, fields defined within the block are automatically
      # added to the group. Without a block, an empty group is initialized.
      #
      # @param name [Symbol, String] the name of the field group
      # @yield optional block for defining fields within the group
      # @return [Array<Symbol>] the array of field names in the group
      #
      # @raise [Familia::Problem] if attempting to nest field groups
      #
      # @example Manual field grouping
      #   class User < Familia::Horreum
      #     field_group :personal_info do
      #       field :name
      #       field :email
      #     end
      #   end
      #
      #   User.personal_info  # => [:name, :email]
      #
      # @example Initialize empty group
      #   class User < Familia::Horreum
      #     field_group :placeholder
      #   end
      #
      #   User.placeholder  # => []
      #
      def field_group(name, &block)

        # Prevent nested field groups
        if @current_field_group
          raise Familia::Problem,
            "Cannot define field group :#{name} while :#{@current_field_group} is being defined. " \
            "Nested field groups are not supported."
        end

        # Initialize group
        field_groups[name.to_sym] ||= []

        if block_given?
          @current_field_group = name.to_sym
          begin
            instance_eval(&block)
          ensure
            @current_field_group = nil
          end
        else
          Familia.debug "[field_group] Created field group :#{name} but no block given"
        end

        field_groups[name.to_sym]
      end

      # Returns the list of all field group names defined for the class.
      #
      # @return [Array<Symbol>] array of field group names
      #
      # @example
      #   class User < Familia::Horreum
      #     field_group :personal_info do
      #       field :name
      #     end
      #     field_group :metadata do
      #       field :created_at
      #     end
      #   end
      #
      #   User.field_groups  # => [
      #     :personal_info => [...],
      #     :metadata => [..]
      #   ]
      #
      def field_groups
        @field_groups_mutex ||= Familia::ThreadSafety::InstrumentedMutex.new('field_groups')
        @field_groups || @field_groups_mutex.synchronize do
          @field_groups ||= {}
        end
      end

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
      # writer method for immediate persistence to the database.
      #
      # @param name [Symbol, String] the name of the field to define. If a method
      #   with the same name already exists, an error is raised.
      # @param as [Symbol, String, false, nil] as the name to use for the accessor method (defaults to name).
      #   If false or nil, no accessor methods are created.
      # @param fast_method [Symbol, false, nil] the name to use for the fast writer method (defaults to :`"#{name}!"`).
      #   If false or nil, no fast writer method is created.
      # @param on_conflict [Symbol] conflict resolution strategy when method already exists:
      #   - :raise - raise error if method exists (default)
      #   - :skip - skip definition if method exists
      #   - :warn - warn but proceed (may overwrite)
      #   - :ignore - proceed silently (may overwrite)
      #
      def field(name, as: name, fast_method: :"#{name}!", on_conflict: :raise)
        field_type = FieldType.new(name, as: as, fast_method: fast_method, on_conflict: on_conflict)
        register_field_type(field_type)
      end

      # Sets or retrieves the suffix for generating Valkey/Redis keys.
      #
      # @param a [String, Symbol, nil] the suffix to set (optional).
      # @param blk [Proc] a block that returns the suffix (optional).
      # @return [String, Symbol] the current suffix or Familia.default_suffix if none is set.
      #
      def suffix(val = nil, &blk)
        @suffix = val || blk if val || !blk.nil?
        @suffix || Familia.default_suffix
      end

      # Sets or retrieves the prefix for generating Valkey/Redis keys.
      #
      # @param a [String, Symbol, nil] the prefix to set (optional).
      # @return [String, Symbol] the current prefix.
      #
      # The exception is only raised when both @prefix is nil/falsy AND name is nil,
      # which typically occurs with anonymous classes that haven't had their prefix
      # explicitly set.
      #
      def prefix(val = nil)
        @prefix = val if val
        @prefix || begin
          if name.nil?
            raise Problem, 'Cannot generate prefix for anonymous class. ' \
                           'Use `prefix` method to set explicitly.'
          end
          config_name.to_sym
        end
      end

      def logical_database(num = nil)
        Familia.trace :LOGICAL_DATABASE_DEF, "instvar:#{@logical_database}", num if Familia.debug?
        @logical_database = num unless num.nil?
        @logical_database || parent&.logical_database
      end

      # Returns the list of field names defined for the class in the order
      # that they were defined. i.e. `field :a; field :b; fields => [:a, :b]`.
      def fields
        @fields_mutex ||= Familia::ThreadSafety::InstrumentedMutex.new('fields')
        @fields || @fields_mutex.synchronize do
          @fields ||= []
        end
      end

      def class_related_fields
        @class_related_fields ||= {}
        @class_related_fields
      end

      def related_fields
        @related_fields ||= {}
        @related_fields
      end

      def relations?
        @has_related_fields ||= false
      end

      # Storage for field type instances
      def field_types
        @field_types_mutex ||= Familia::ThreadSafety::InstrumentedMutex.new('field_types')
        @field_types || @field_types_mutex.synchronize do
          @field_types ||= {}
        end
      end

      # Returns a hash mapping field names to method names for backward compatibility
      def field_method_map
        field_types.transform_values(&:method_name)
      end

      # Get fields for serialization (excludes transients)
      def persistent_fields
        fields.select do |field|
          field_types[field]&.persistent?
        end
      end

      # Get fields that are not persisted to the database (transients)
      def transient_fields
        fields.select do |field|
          field_types[field]&.transient?
        end
      end

      # Register a field type instance with this class
      #
      # This method installs the field type's methods and registers it
      # for later reference. It maintains backward compatibility by
      # creating FieldDefinition objects.
      #
      # @param field_type [FieldType] The field type to register
      #
      def register_field_type(field_type)
        fields << field_type.name
        field_type.install(self)
        # Complete the registration after installation. If we do this beforehand
        # we can run into issues where it looks like it's already installed.
        field_types[field_type.name] = field_type

        # Add to current field group if one is active
        if @current_field_group
          @field_groups[@current_field_group] << field_type.name
        end

        # Freeze the field_type to ensure immutability (maintains Data class heritage)
        field_type.freeze
      end

      # Retrieves feature options for the current class.
      #
      # Feature options are stored **per-class** in instance variables, ensuring
      # complete isolation between different Familia::Horreum subclasses. Each
      # class maintains its own @feature_options hash that does not interfere
      # with other classes' configurations.
      #
      # @param feature_name [Symbol, String, nil] the name of the feature to get options for.
      #   If nil, returns the entire feature options hash for this class.
      # @return [Hash] the feature options hash, either for a specific feature or all features
      #
      # @example Getting options for a specific feature
      #   class MyModel < Familia::Horreum
      #     feature :object_identifier, generator: :uuid_v4
      #   end
      #
      #   MyModel.feature_options(:object_identifier) #=> {generator: :uuid_v4}
      #   MyModel.feature_options                     #=> {object_identifier: {generator: :uuid_v4}}
      #
      # @example Per-class isolation
      #   class UserModel < Familia::Horreum
      #     feature :object_identifier, generator: :uuid_v4
      #   end
      #
      #   class SessionModel < Familia::Horreum
      #     feature :object_identifier, generator: :hex
      #   end
      #
      #   UserModel.feature_options(:object_identifier)    #=> {generator: :uuid_v4}
      #   SessionModel.feature_options(:object_identifier) #=> {generator: :hex}
      #
      def feature_options(feature_name = nil)
        @feature_options ||= {}
        return @feature_options if feature_name.nil?

        @feature_options[feature_name.to_sym] || {}
      end

      # Add feature options for a specific feature
      #
      # This method provides a clean way for features to set their default options
      # without worrying about initialization state. Similar to register_field_type
      # for field types.
      #
      # Feature options are stored at the **class level** using instance variables,
      # ensuring complete isolation between different Familia::Horreum subclasses.
      # Each class maintains its own @feature_options hash.
      #
      # @param feature_name [Symbol] The feature name
      # @param options [Hash] The options to add/merge
      # @return [Hash] The updated options for the feature
      #
      # @note This method only sets defaults for options that don't already exist,
      #   using the ||= operator to prevent overwrites.
      #
      # @example Per-class storage behavior
      #   class ModelA < Familia::Horreum
      #     # This stores options in ModelA's @feature_options
      #     add_feature_options(:my_feature, key: 'value_a')
      #   end
      #
      #   class ModelB < Familia::Horreum
      #     # This stores options in ModelB's @feature_options (separate from ModelA)
      #     add_feature_options(:my_feature, key: 'value_b')
      #   end
      #
      def add_feature_options(feature_name, **options)
        @feature_options ||= {}
        @feature_options[feature_name.to_sym] ||= {}

        # Only set defaults for options that don't already exist
        options.each do |key, value|
          @feature_options[feature_name.to_sym][key] ||= value
        end

        @feature_options[feature_name.to_sym]
      end

      private

      # Hook to detect silent overwrites and handle conflicts
      def method_added(method_name)
        super

        # Find the field type that generated this method
        field_type = field_types.values.find { |ft| ft.generated_methods.include?(method_name) }
        return unless field_type

        case field_type.on_conflict
        when :warn
          warn <<~WARNING

            WARNING: Method >>> #{method_name} <<< was redefined after field definition.
            Field functionality may be broken. Consider using a different name
            with field(:#{field_type.name}, as: :other_name)

            Called from:
            #{Familia.pretty_stack(limit: 3)}

          WARNING
        when :raise
          raise ArgumentError, "Method >>> #{method_name} <<< already defined for #{self}"
        when :skip, :ignore
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

      # Fast attribute accessor method for immediate DB persistence.
      #
      # @param field_name [Symbol, String] the name of the horreum model attribute
      # @param method_name [Symbol, String] the name of the regular accessor method
      # @param fast_method_name [Symbol, String] the name of the fast method (must end with '!')
      # @param on_conflict [Symbol] conflict resolution strategy for method name conflicts
      #
      # @return [void]
      #
      # @raise [ArgumentError] if fast_method_name doesn't end with '!'
      #
      # @note Generated method behavior:
      #   - Without args: Retrieves current value from Valkey/Redis
      #   - With value: Sets and immediately persists to Valkey/Redis
      #   - Returns boolean indicating success for writes
      #   - Bypasses object-level caching and expiration updates
      #
      # @example
      #   # Creates a method like: username!(value = nil)
      #   define_fast_writer_method(:username, :username, :username!, :raise)
      #
      def define_fast_writer_method(field_name, method_name, fast_method_name, on_conflict)
        raise ArgumentError, 'Must end with !' unless fast_method_name.to_s.end_with?('!')

        handle_method_conflict(fast_method_name, on_conflict) do
          # Fast attribute accessor method for the '#{field_name}' attribute.
          # This method provides immediate read and write access to the attribute
          # in the database.
          #
          # When called without arguments, it retrieves the current value of the
          # attribute from the database.
          # When called with an argument, it immediately persists the new value to
          # the database.
          #
          # @overload #{method_name}
          #   Retrieves the current value of the attribute from the database.
          #   @return [Object] the current value of the attribute.
          #
          # @overload #{method_name}(value)
          #   Sets and immediately persists the new value of the attribute to
          #   the database.
          #   @param value [Object] the new value to set for the attribute.
          #   @return [Object] the newly set value.
          #
          # @raise [ArgumentError] if more than one argument is provided.
          # @raise [RuntimeError] if an exception occurs during the execution of
          #   the method.
          #
          # @note This method bypasses any object-level caching and interacts
          #   directly with the database. It does not trigger updates to other attributes
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
            # Handle Redis::Future objects during transactions
            return hget field_name if val.nil? || val.is_a?(Redis::Future)

            begin
              # Trace the operation if debugging is enabled.
              Familia.trace :FAST_WRITER, nil, "#{field_name}: #{val.inspect}" if Familia.debug?

              # Convert the provided value to a format suitable for Database storage.
              prepared = serialize_value(val)
              Familia.debug "[define_fast_writer_method] #{fast_method_name} val: #{val.class} prepared: #{prepared.class}"

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

        return '' unless source_location

        path = Familia.pretty_path(source_location[0])
        line = source_location[1]
        " (defined at #{path}:#{line})"
      end
    end
  end
end
