# lib/familia/field_type.rb

module Familia
  # Base class for all field types in Familia
  #
  # Field types encapsulate the behavior for different kinds of fields,
  # including how their getter/setter methods are defined and how values
  # are serialized/deserialized.
  #
  # @example Creating a custom field type
  #   class TimestampFieldType < Familia::FieldType
  #     def define_setter(klass)
  #       field_name = @name
  #       klass.define_method :"#{@method_name}=" do |value|
  #         timestamp = value.is_a?(Time) ? value.to_i : value
  #         instance_variable_set(:"@#{field_name}", timestamp)
  #       end
  #     end
  #
  #     def define_getter(klass)
  #       field_name = @name
  #       klass.define_method @method_name do
  #         timestamp = instance_variable_get(:"@#{field_name}")
  #         timestamp ? Time.at(timestamp) : nil
  #       end
  #     end
  #   end
  #
  class FieldType
    attr_reader :name, :options, :method_name, :fast_method_name, :on_conflict, :loggable

    using Familia::Refinements::TimeLiterals

    # Initialize a new field type
    #
    # @param name [Symbol] The field name
    # @param as [Symbol, String, false] The method name (defaults to field name)
    #   If false, no accessor methods are created
    # @param fast_method [Symbol, String, false] The fast method name
    #   (defaults to "#{name}!"). If false, no fast method is created
    # @param on_conflict [Symbol] Conflict resolution strategy when method
    #   already exists (:raise, :skip, :warn, :overwrite)
    # @param loggable [Boolean] Whether this field should be included in
    #   serialization and logging operations (default: true)
    # @param options [Hash] Additional options for the field type
    #
    def initialize(name, as: name, fast_method: :"#{name}!", on_conflict: :raise, loggable: true, **options)
      @name = name.to_sym
      @method_name = as == false ? nil : as.to_sym
      @fast_method_name = fast_method == false ? nil : fast_method&.to_sym

      # Validate fast method name format
      if @fast_method_name && !@fast_method_name.to_s.end_with?('!')
        raise ArgumentError, "Fast method name must end with '!' (got: #{@fast_method_name})"
      end

      @on_conflict = on_conflict
      @loggable = loggable
      @options = options
    end

    # Install this field type on a class
    #
    # This method defines all necessary methods on the target class
    # and registers the field type for later reference.
    #
    # @param klass [Class] The class to install this field type on
    #
    def install(klass)
      if @method_name
        # For skip strategy, check for any method conflicts first
        if @on_conflict == :skip
          has_getter_conflict = klass.method_defined?(@method_name) || klass.private_method_defined?(@method_name)
          has_setter_conflict = klass.method_defined?(:"#{@method_name}=") || klass.private_method_defined?(:"#{@method_name}=")

          # If either getter or setter conflicts, skip the whole field
          return if has_getter_conflict || has_setter_conflict
        end

        define_getter(klass)
        define_setter(klass)
      end

      define_fast_writer(klass) if @fast_method_name
    end

    # Define the getter method on the target class
    #
    # Subclasses can override this to customize getter behavior.
    # The default implementation creates a simple attr_reader equivalent.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_getter(klass)
      field_name = @name
      method_name = @method_name

      handle_method_conflict(klass, method_name) do
        klass.define_method method_name do
          instance_variable_get(:"@#{field_name}")
        end
      end
    end

    # Define the setter method on the target class
    #
    # Subclasses can override this to customize setter behavior.
    # The default implementation creates a simple attr_writer equivalent.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_setter(klass)
      field_name = @name
      method_name = @method_name

      handle_method_conflict(klass, :"#{method_name}=") do
        klass.define_method :"#{method_name}=" do |value|
          instance_variable_set(:"@#{field_name}", value)
        end
      end
    end

    # Define the fast writer method on the target class
    #
    # Fast methods provide direct database access for immediate persistence.
    # Subclasses can override this to customize fast method behavior.
    #
    # @param klass [Class] The class to define the method on
    #
    def define_fast_writer(klass)
      return unless @fast_method_name&.to_s&.end_with?('!')

      field_name = @name
      method_name = @method_name
      fast_method_name = @fast_method_name

      handle_method_conflict(klass, fast_method_name) do
        klass.define_method fast_method_name do |*args|
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0 or 1)" if args.size > 1

          val = args.first

          # If no value provided, return current stored value
          return hget(field_name) if val.nil?

          begin
            # Trace the operation if debugging is enabled
            Familia.trace :FAST_WRITER, nil, "#{field_name}: #{val.inspect}" if Familia.debug?

            # Convert value for database storage
            prepared = serialize_value(val)
            Familia.ld "[FieldType#define_fast_writer] #{fast_method_name} val: #{val.class} prepared: #{prepared.class}"

            # Use the setter method to update instance variable
            send(:"#{method_name}=", val) if method_name

            # Persist to database immediately
            ret = hset(field_name, prepared)
            ret.zero? || ret.positive?
          rescue Familia::Problem => e
            raise "#{fast_method_name} method failed: #{e.message}", e.backtrace
          end
        end
      end
    end

    # Whether this field should be persisted to the database
    #
    # @return [Boolean] true if field should be persisted
    #
    def persistent?
      true
    end

    def transient?
      !persistent?
    end

    # The category for this field type (used for filtering)
    #
    # @return [Symbol] the field category
    #
    def category
      :field
    end

    # Serialize a value for database storage
    #
    # Subclasses can override this to customize serialization.
    # The default implementation passes values through unchanged.
    #
    # @param value [Object] The value to serialize
    # @param _record [Object] The record instance (for context)
    # @return [Object] The serialized value
    #
    def serialize(value, _record = nil)
      value
    end

    # Deserialize a value from database storage
    #
    # Subclasses can override this to customize deserialization.
    # The default implementation passes values through unchanged.
    #
    # @param value [Object] The value to deserialize
    # @param _record [Object] The record instance (for context)
    # @return [Object] The deserialized value
    #
    def deserialize(value, _record = nil)
      value
    end

    # Returns all method names generated for this field (used for conflict detection)
    #
    # @return [Array<Symbol>] Array of method names this field type generates
    #
    def generated_methods
      [@method_name, @fast_method_name].compact
    end

    # Enhanced inspection output for debugging
    #
    # @return [String] Human-readable representation
    #
    def inspect
      attributes = [
        "name=#{@name}",
        "method_name=#{@method_name}",
        "fast_method_name=#{@fast_method_name}",
        "on_conflict=#{@on_conflict}",
        "category=#{category}"
      ]
      "#<#{self.class.name} #{attributes.join(' ')}>"
    end
    alias to_s inspect

    private

    # Handle method name conflicts during definition
    #
    # @param klass [Class] The target class
    # @param method_name [Symbol] The method name to define
    # @yield Block that defines the method
    #
    def handle_method_conflict(klass, method_name)
      case @on_conflict
      when :skip
        return if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
      when :warn
        if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
          warn <<~WARNING

            WARNING: Method >>> #{method_name} <<< already exists on #{klass}.
            Field functionality may be broken. Consider using a different name
            with field(:#{@name}, as: :other_name)

            Called from:
            #{Familia.pretty_stack(limit: 3)}

          WARNING
        end
      when :raise
        if klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
          raise ArgumentError, "Method >>> #{method_name} <<< already defined for #{klass}"
        end
      when :overwrite
        # Proceed silently - allow overwrite
      else
        raise ArgumentError, "Unknown conflict resolution strategy: #{@on_conflict}"
      end

      yield
    end
  end
end
