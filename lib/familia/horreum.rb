# lib/familia/horreum.rb

module Familia
  #
  # Horreum: A module for managing Redis-based object storage and relationships
  #
  # Key features:
  # * Provides instance-level access to a single hash in Redis
  # * Includes Familia for class/module level access to Database types and operations
  # * Uses 'hashkey' to define a Database hash referred to as "object"
  # * Applies a default expiry (5 years) to all keys
  #
  # Metaprogramming:
  # * The class << self block defines class-level behavior
  # * The `inherited` method extends ClassMethods to subclasses like
  #  `MyModel` in the example below
  #
  # Usage:
  #   class MyModel < Familia::Horreum
  #     field :name
  #     field :email
  #   end
  #
  class Horreum
    include Familia::Base

    # Singleton Class Context
    #
    # The code within this block operates on the singleton class (also known as
    # eigenclass or metaclass) of the current class. This means:
    #
    # 1. Methods defined here become class methods, not instance methods.
    # 2. Constants and variables set here belong to the class, not instances.
    # 3. This is the place to define class-level behavior and properties.
    #
    # Use this context for:
    # * Defining class methods
    # * Setting class-level configurations
    # * Creating factory methods
    # * Establishing relationships with other classes
    #
    # Example:
    #   class MyClass
    #     class << self
    #       def class_method
    #         puts "This is a class method"
    #       end
    #     end
    #   end
    #
    #   MyClass.class_method  # => "This is a class method"
    #
    # Note: Changes made here affect the class itself and all future instances,
    # but not existing instances of the class.
    #
    class << self
      attr_accessor :parent
      # TODO: Where are we calling dbclient= from now with connection pool?
      attr_writer :dbclient, :dump_method, :load_method
      attr_reader :has_relations

      # Extends ClassMethods to subclasses and tracks Familia members
      def inherited(member)
        Familia.trace :HORREUM, nil, "Welcome #{member} to the family", caller(1..1) if Familia.debug?
        member.extend(DefinitionMethods)
        member.extend(ManagementMethods)
        member.extend(Connection)
        member.extend(Features)

        # Tracks all the classes/modules that include Familia. It's
        # 10pm, do you know where you Familia members are?
        Familia.members << member
        super
      end
    end

    # Instance initialization
    # This method sets up the object's state, including Redis-related data.
    #
    # Usage:
    #
    #   Session.new("abc123", "user456")                   # positional (brittle)
    #   Session.new(sessid: "abc123", custid: "user456")   # hash (robust)
    #   Session.new({sessid: "abc123", custid: "user456"}) # legacy hash (robust)
    #
    def initialize(*args, **kwargs)
      Familia.ld "[Horreum] Initializing #{self.class}"
      initialize_relatives

      # No longer auto-create a key field - the identifier method will
      # directly use the field specified by identifier_field

      # Detect if first argument is a hash (legacy support)
      if args.size == 1 && args.first.is_a?(Hash) && kwargs.empty?
        kwargs = args.first
        args = []
      end

      # Initialize object with arguments using one of three strategies:
      #
      # 1. **Keyword Arguments** (Recommended): Order-independent field assignment
      #    Example: Customer.new(name: "John", email: "john@example.com")
      #    - Robust against field reordering
      #    - Self-documenting
      #    - Only sets provided fields
      #
      # 2. **Positional Arguments** (Legacy): Field assignment by definition order
      #    Example: Customer.new("john@example.com", "password123")
      #    - Brittle: breaks if field order changes
      #    - Compact syntax
      #    - Maps to fields in class definition order
      #
      # 3. **No Arguments**: Object created with all fields as nil
      #    - Minimal memory footprint in Redis
      #    - Fields set on-demand via accessors or save()
      #    - Avoids default value conflicts with nil-skipping serialization
      #
      # Note: We iterate over self.class.fields (not kwargs) to ensure only
      # defined fields are set, preventing typos from creating undefined attributes.
      #
      if kwargs.any?
        initialize_with_keyword_args(**kwargs)
      elsif args.any?
        initialize_with_positional_args(*args)
      else
        Familia.ld "[Horreum] #{self.class} initialized with no arguments"
        # Default values are intentionally NOT set here to:
        # - Maintain Database memory efficiency (only store non-nil values)
        # - Avoid conflicts with nil-skipping serialization logic
        # - Preserve consistent exists? behavior (empty vs default-filled objects)
        # - Keep initialization lightweight for unused fields
      end

      # Implementing classes can define an init method to do any
      # additional initialization. Notice that this is called
      # after the fields are set.
      init
    end

    def init(*args, **kwargs)
      # Default no-op
    end

    # Sets up related Database objects for the instance
    # This method is crucial for establishing Redis-based relationships
    #
    # This needs to be called in the initialize method.
    #
    def initialize_relatives
      # Generate instances of each DataType. These need to be
      # unique for each instance of this class so they can piggyback
      # on the specifc index of this instance.
      #
      # i.e.
      #     familia_object.dbkey              == v1:bone:INDEXVALUE:object
      #     familia_object.related_object.dbkey == v1:bone:INDEXVALUE:name
      #
      self.class.related_fields.each_pair do |name, data_type_definition|
        klass = data_type_definition.klass
        opts = data_type_definition.opts
        Familia.ld "[#{self.class}] initialize_relatives #{name} => #{klass} #{opts.keys}"

        # As a subclass of Familia::Horreum, we add ourselves as the parent
        # automatically. This is what determines the dbkey for DataType
        # instance and which database connection.
        #
        #   e.g. If the parent's dbkey is `customer:customer_id:object`
        #     then the dbkey for this DataType instance will be
        #     `customer:customer_id:name`.
        #
        opts[:parent] = self # unless opts.key(:parent)

        suffix_override = opts.fetch(:suffix, name)

        # Instantiate the DataType object and below we store it in
        # an instance variable.
        related_object = klass.new suffix_override, opts

        # Freezes the related_object, making it immutable.
        # This ensures the object's state remains consistent and prevents any modifications,
        # safeguarding its integrity and making it thread-safe.
        # Any attempts to change the object after this will raise a FrozenError.
        related_object.freeze

        # e.g. customer.name  #=> `#<Familia::HashKey:0x0000...>`
        instance_variable_set :"@#{name}", related_object
      end
    end

    # Initializes the object with positional arguments.
    # Maps each argument to a corresponding field in the order they are defined.
    #
    # @param args [Array] List of values to be assigned to fields
    # @return [Array<Symbol>] List of field names that were successfully updated
    #   (i.e., had non-nil values assigned)
    # @private
    def initialize_with_positional_args(*args)
      Familia.trace :INITIALIZE_ARGS, dbclient, args, caller(1..1) if Familia.debug?
      self.class.fields.zip(args).filter_map do |field, value|
        if value
          send(:"#{field}=", value)
          field.to_sym
        end
      end
    end
    private :initialize_with_positional_args

    # Initializes the object with keyword arguments.
    # Assigns values to fields based on the provided hash of field names and values.
    # Handles both symbol and string keys to accommodate different sources of data.
    #
    # @param fields [Hash] Hash of field names (as symbols or strings) and their values
    # @return [Array<Symbol>] List of field names that were successfully updated
    #   (i.e., had non-nil values assigned)
    # @private
    def initialize_with_keyword_args(**fields)
      Familia.trace :INITIALIZE_KWARGS, dbclient, fields.keys, caller(1..1) if Familia.debug?
      self.class.fields.filter_map do |field|
        # Database will give us field names as strings back, but internally
        # we use symbols. So we check for both.
        value = fields[field.to_sym] || fields[field.to_s]
        if value
          # Use the mapped method name, not the field name
          method_name = self.class.field_method_map[field] || field
          send(:"#{method_name}=", value)
          field.to_sym
        end
      end
    end
    private :initialize_with_keyword_args

    def initialize_with_keyword_args_deserialize_value(**fields)
      # Deserialize Database string values back to their original types
      deserialized_fields = fields.transform_values { |value| deserialize_value(value) }
      initialize_with_keyword_args(**deserialized_fields)
    end

    # A thin wrapper around the private initialize method that accepts a field
    # hash and refreshes the existing object.
    #
    # This method is part of horreum.rb rather than serialization.rb because it
    # operates solely on the provided values and doesn't query Database or other
    # external sources. That's why it's called "optimistic" refresh: it assumes
    # the provided values are correct and updates the object accordingly.
    #
    # @see #refresh!
    #
    # @param fields [Hash] A hash of field names and their new values to update
    #   the object with.
    # @return [Array] The list of field names that were updated.
    def optimistic_refresh(**fields)
      Familia.ld "[optimistic_refresh] #{self.class} #{dbkey} #{fields.keys}"
      initialize_with_keyword_args_deserialize_value(**fields)
    end

    # Determines the unique identifier for the instance
    # This method is used to generate dbkeys for the object
    # Returns nil for unsaved objects (following standard ORM patterns)
    def identifier
      definition = self.class.identifier_field
      return nil if definition.nil?

      # Call the identifier field or proc (validation already done at class definition time)
      unique_id = case definition
                  when Symbol, String
                    send(definition)
                  when Proc
                    definition.call(self)
                  end

      # Return nil for unpopulated identifiers (like unsaved ActiveRecord objects)
      # Only raise errors when the identifier is actually needed for Redis operations
      return nil if unique_id.nil? || unique_id.to_s.empty?

      unique_id
    end

    attr_writer :dbclient

    # Summon the mystical Database connection from the depths of instance or class.
    #
    # This method is like a magical divining rod, always pointing to the nearest
    # source of Database goodness. It first checks if we have a personal Redis
    # connection (@dbclient), and if not, it borrows the class's connection.
    #
    # @return [Redis] A shimmering Database connection, ready for your bidding.
    #
    # @example Finding your Database way
    #   puts object.dbclient
    #   # => #<Redis client v5.4.1 for redis://localhost:6379/0>
    #
    def dbclient
      conn = Fiber[:familia_transaction] || @dbclient || self.class.dbclient
      # conn.select(self.class.logical_database)
      conn
    end

    def generate_id
      @objid ||= Familia.generate_id # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    # The principle is: **If Familia objects have `to_s`, then they should work
    # everywhere strings are expected**, including as Database hash field names.
    def to_s
      # Enable polymorphic string usage for Familia objects
      # This allows passing Familia objects directly where strings are expected
      # without requiring explicit .identifier calls
      return super if identifier.to_s.empty?
      identifier.to_s
    end
  end
end

require_relative 'horreum/definition_methods'
require_relative 'horreum/management_methods'
require_relative 'horreum/database_commands'
require_relative 'horreum/connection'
require_relative 'horreum/serialization'
require_relative 'horreum/settings'
require_relative 'horreum/utils'
