# lib/familia/features/safe_dump.rb

# rubocop:disable ThreadSafety/ClassInstanceVariable
#
#   Class instance variables are used here for feature configuration
#   (e.g., @dump_method, @load_method). These are set once and not mutated
#   at runtime, so thread safety is not a concern for this feature.
#
module Familia::Features
  # SafeDump is a mixin that allows models to define a list of fields that are
  # safe to dump. This is useful for serializing objects to JSON or other
  # formats where you want to ensure that only certain fields are exposed.
  #
  # To use SafeDump, include it in your model and use the DSL methods to define
  # safe dump fields. The fields can be either symbols or hashes. If a field is
  # a symbol, the method with the same name will be called on the object to
  # retrieve the value. If the field is a hash, the key is the field name and
  # the value is a lambda that will be called with the object as an argument.
  # The hash syntax allows you to:
  #   * define a field name that is different from the method name
  #   * define a field that requires some computation on-the-fly
  #   * define a field that is not a method on the object
  #
  # Example:
  #
  #   feature :safe_dump
  #
  #   safe_dump_field :objid
  #   safe_dump_field :updated
  #   safe_dump_field :created
  #   safe_dump_field :active, ->(obj) { obj.active? }
  #
  # Alternatively, you can define multiple fields at once:
  #
  #   safe_dump_fields :objid, :updated, :created,
  #                    { active: ->(obj) { obj.active? } }
  #
  # Internally, all fields are normalized to the hash syntax and stored in
  # @safe_dump_field_map. `SafeDump.safe_dump_fields` returns only the list
  # of symbols in the order they were defined.
  #
  module SafeDump
    @dump_method = :to_json
    @load_method = :from_json

    def self.included(base)
      Familia.trace(:LOADED, self, base, caller(1..1)) if Familia.debug?
      base.extend ClassMethods

      # Initialize the safe dump field map
      base.instance_variable_set(:@safe_dump_field_map, {})
    end

    # SafeDump::ClassMethods
    #
    # These methods become available on the model class
    module ClassMethods
      # Define a single safe dump field
      # @param field_name [Symbol] The name of the field
      # @param callable [Proc, nil] Optional callable to transform the value
      def safe_dump_field(field_name, callable = nil)
        @safe_dump_field_map ||= {}

        field_name = field_name.to_sym
        field_value = callable || lambda { |obj|
          if obj.respond_to?(:[]) && obj[field_name]
            obj[field_name] # Familia::DataType classes
          elsif obj.respond_to?(field_name)
            obj.send(field_name) # Regular method calls
          end
        }

        @safe_dump_field_map[field_name] = field_value
      end

      # Define multiple safe dump fields at once
      # @param fields [Array] Mixed array of symbols and hashes
      def safe_dump_fields(*fields)
        # If no arguments, return field names (getter behavior)
        return safe_dump_field_names if fields.empty?

        # Otherwise, define fields (setter behavior)
        fields.each do |field|
          if field.is_a?(Symbol)
            safe_dump_field(field)
          elsif field.is_a?(Hash)
            field.each do |name, callable|
              safe_dump_field(name, callable)
            end
          end
        end
      end

      # Returns an array of safe dump field names in the order they were defined
      def safe_dump_field_names
        (@safe_dump_field_map || {}).keys
      end

      # Returns the field map used for dumping
      def safe_dump_field_map
        @safe_dump_field_map || {}
      end

      # Legacy method for setting safe dump fields (for backward compatibility)
      def set_safe_dump_fields(*fields)
        safe_dump_fields(*fields)
      end
    end

    # Returns a hash of safe fields and their values. This method
    # calls the callables defined in the safe_dump_field_map with
    # the instance object as an argument.
    #
    # The return values are not cached, so if you call this method
    # multiple times, the callables will be called each time.
    #
    # Example:
    #
    #   class Customer < Familia::HashKey
    #     include SafeDump
    #     @safe_dump_fields = [
    #       :name,
    #       { :active => ->(cust) { cust.active? } }
    #     ]
    #
    #     def active?
    #       true # or false
    #     end
    #
    #     cust = Customer.new :name => 'Lucy'
    #     cust.safe_dump
    #     #=> { :name => 'Lucy', :active => true }
    #
    def safe_dump
      self.class.safe_dump_field_map.transform_values do |callable|
        transformed_value = callable.call(self)

        # If the value is a relative ancestor of SafeDump we can
        # call safe_dump on it, otherwise we'll just return the value as-is.
        if transformed_value.is_a?(SafeDump)
          transformed_value.safe_dump
        else
          transformed_value
        end
      end
    end

    extend ClassMethods

    Familia::Base.add_feature self, :safe_dump
  end
end
# rubocop:enable ThreadSafety/ClassInstanceVariable
