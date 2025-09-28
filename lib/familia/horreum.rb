# lib/familia/horreum.rb

require_relative 'horreum/subclass/definition'
require_relative 'horreum/subclass/management'
require_relative 'horreum/shared/settings'
require_relative 'horreum/core'

module Familia
  #
  # Horreum: A Valkey/Redis-backed ORM base class providing field definitions and DataType relationships
  #
  # Familia::Horreum serves as the foundation for creating Ruby objects that are persisted
  # to and retrieved from Valkey/Redis. It provides a comprehensive field system, DataType
  # relationships, and automated key generation for seamless object-relational mapping.
  #
  # Core Features:
  # * Field definition system with automatic getter/setter/fast writer generation
  # * DataType relationships (sets, lists, hashes, sorted sets, counters, locks)
  # * Flexible identifier strategies (symbols, procs, arrays)
  # * Automatic Redis key generation and management
  # * Feature system for modular functionality (expiration, safe_dump, relationships)
  # * Thread-safe DataType instances with automatic freezing
  # * Multiple initialization patterns for different use cases
  #
  # Architecture:
  # * Inheriting classes automatically extend definition and management methods
  # * Instance-level DataTypes are created per object with unique Redis keys
  # * Class-level DataTypes are shared across all instances
  # * All objects tracked in Familia.members for reloading and introspection
  #
  # Usage:
  #   class User < Familia::Horreum
  #     identifier_field :email
  #     field :name
  #     field :created_at
  #     set :tags
  #     list :activity_log
  #     feature :expiration
  #   end
  #
  #   user = User.new(email: "john@example.com", name: "John")
  #   user.tags << "premium"
  #   user.save
  #
  class Horreum
    include Familia::Base
    include Familia::Horreum::Core
    include Familia::Horreum::Settings

    using Familia::Refinements::TimeLiterals

    # Class-Level Inheritance and Extension Management
    #
    # This singleton class block defines the metaclass behavior that governs how
    # Familia::Horreum subclasses are configured and extended when they inherit.
    #
    # Key Responsibilities:
    # * Automatically extend subclasses with essential functionality modules
    # * Register new classes in Familia.members for tracking and reloading
    # * Provide class-level attribute accessors for configuration
    # * Establish the inheritance chain that enables the Horreum ORM pattern
    #
    # When a class inherits from Horreum, the inherited() hook automatically:
    # * Extends DefinitionMethods (field, identifier_field, dbkey definitions)
    # * Extends ManagementMethods (create, find, destroy operations)
    # * Extends Connection (database client and connection management)
    # * Extends Features (feature loading and configuration)
    # * Registers the class in Familia.members for introspection
    #
    # Class-Level Attributes:
    # * @parent - Parent object reference for nested relationships
    # * @dbclient - Database connection override for this class
    # * @dump_method/@load_method - Serialization method configuration
    # * @has_relations - Flag indicating if DataType relationships are defined
    #
    class << self
      attr_accessor :parent
      # TODO: Where are we calling dbclient= from now with connection pool?
      attr_writer :dbclient, :dump_method, :load_method
      attr_reader :has_relations

      # Extends ClassMethods to subclasses and tracks Familia members
      def inherited(member)
        Familia.trace :HORREUM, nil, "Welcome #{member} to the family" if Familia.debug?

        # Class-level functionality extensions:
        member.extend(Familia::Horreum::DefinitionMethods)    # field(), identifier_field(), dbkey()
        member.extend(Familia::Horreum::ManagementMethods)    # create(), find(), destroy!()
        member.extend(Familia::Horreum::Connection)           # dbclient, connection management
        member.extend(Familia::Features) # feature() method for optional modules

        # Copy parent class configuration to child class
        # This implements conventional ORM inheritance behavior where child classes
        # automatically inherit all parent configuration without manual copying
        parent_class = member.superclass
        if parent_class.respond_to?(:identifier_field) && parent_class != Familia::Horreum
          # Copy essential configuration instance variables from parent
          if parent_class.identifier_field
            member.instance_variable_set(:@identifier_field, parent_class.identifier_field)
          end

          # Copy field system configuration
          member.instance_variable_set(:@fields, parent_class.fields.dup) if parent_class.fields&.any?

          if parent_class.respond_to?(:field_types) && parent_class.field_types&.any?
            # Copy field_types hash (FieldType instances are frozen/immutable and can be safely shared)
            copied_field_types = parent_class.field_types.dup
            member.instance_variable_set(:@field_types, copied_field_types)
            # Re-install field methods on the child class using proper method name detection
            parent_class.field_types.each do |_name, field_type|
              # Collect all method names that field_type.install will create
              methods_to_check = [
                field_type.method_name,
                (field_type.method_name ? :"#{field_type.method_name}=" : nil),
                field_type.fast_method_name,
              ].compact

              # Only install if none of the methods already exist
              methods_exist = methods_to_check.any? do |method_name|
                member.method_defined?(method_name) || member.private_method_defined?(method_name)
              end

              field_type.install(member) unless methods_exist
            end
          end

          # Copy features configuration
          if parent_class.respond_to?(:features_enabled) && parent_class.features_enabled&.any?
            member.instance_variable_set(:@features_enabled, parent_class.features_enabled.dup)
          end

          # Copy other configuration using consistent instance variable access
          if (prefix = parent_class.instance_variable_get(:@prefix))
            member.instance_variable_set(:@prefix, prefix)
          end
          if (suffix = parent_class.instance_variable_get(:@suffix))
            member.instance_variable_set(:@suffix, suffix)
          end
          if (logical_db = parent_class.instance_variable_get(:@logical_database))
            member.instance_variable_set(:@logical_database, logical_db)
          end
          if (default_exp = parent_class.instance_variable_get(:@default_expiration))
            member.instance_variable_set(:@default_expiration, default_exp)
          end

          # Copy DataType relationships
          if parent_class.class_related_fields&.any?
            member.instance_variable_set(:@class_related_fields, parent_class.class_related_fields.dup)
          end
          if parent_class.related_fields&.any?
            member.instance_variable_set(:@related_fields, parent_class.related_fields.dup)
          end
          if parent_class.instance_variable_get(:@has_relations)
            member.instance_variable_set(:@has_relations,
                                         parent_class.instance_variable_get(:@has_relations))
          end
        end

        # Track all classes that inherit from Horreum
        Familia.members << member

        # Set up automatic instance tracking using built-in class_sorted_set
        member.class_sorted_set :instances

        super
      end
    end

    attr_writer :dbclient

    # Instance initialization
    # This method sets up the object's state, including Valkey/Redis-related data.
    #
    # Usage:
    #
    #   `Session.new("abc123", "user456")`                   # positional (brittle)
    #   `Session.new(sessid: "abc123", custid: "user456")`   # hash (robust)
    #   `Session.new({sessid: "abc123", custid: "user456"})` # legacy hash (robust)
    #
    def initialize(*args, **kwargs)
      Familia.trace :INITIALIZE, nil, "Initializing #{self.class}" if Familia.debug?
      initialize_relatives

      # No longer auto-create a key field - the identifier method will
      # directly use the field specified by identifier_field

      # Detect if first argument is a hash (legacy support)
      if args.size == 1 && args.first.is_a?(Hash) && kwargs.empty?
        kwargs = args.first
        args = []
      end

      # Initialize object with arguments using one of four strategies:
      #
      # 1. **Identifier** (Recommended for lookups): A single argument is
      #     treated as the identifier. Robust and convenient for creating
      #     objects from an ID. e.g. `Customer.new("cust_123")`
      #
      # 2. **Keyword Arguments** (Recommended for creation): Order-independent
      #     field assignment
      #    e.g. Customer.new(name: "John", email: "john@example.com")
      #
      # 3. **Positional Arguments** (Legacy): Field assignment by definition order
      #    e.g. Customer.new("cust_123", "John", "john@example.com")
      #
      # 4. **No Arguments**: Object created with all fields as nil
      #
      if args.size == 1 && kwargs.empty?
        id_field = self.class.identifier_field
        send(:"#{id_field}=", args.first)
      elsif kwargs.any?
        initialize_with_keyword_args(**kwargs)
      elsif args.any?
        initialize_with_positional_args(*args)
      elsif Familia.debug?
        Familia.trace :INITIALIZE, nil, "#{self.class} initialized with no arguments"
        # Default values are intentionally NOT set here
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
    # This method is crucial for establishing Valkey/Redis-based relationships
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
        Familia.trace :INITIALIZE_RELATIVES, nil, "#{name} => #{klass} #{opts.keys}" if Familia.debug?

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
      # Only raise errors when the identifier is actually needed for db operations
      return nil if unique_id.nil? || unique_id.to_s.empty?

      unique_id
    end

    # Returns the Database connection for the instance using Chain of Responsibility pattern.
    #
    # This method uses a chain of handlers to resolve connections in priority order:
    # 1. FiberTransactionHandler - Fiber[:familia_transaction] (active transaction)
    # 2. DefaultConnectionHandler - Accesses self.dbclient
    # 3. DefaultConnectionHandler - Accesses self.class.dbclient
    # 4. GlobalFallbackHandler - Familia.dbclient(uri || logical_database) (global fallback)
    #
    # @return [Redis] the Database connection instance.
    #
    def dbclient
      @instance_connection_chain ||= build_connection_chain
      @instance_connection_chain.handle(nil)
    end

    def generate_id
      @objid ||= Familia.generate_id
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

    private

    # Initializes the object with positional arguments.
    # Maps each argument to a corresponding field in the order they are defined.
    #
    # @param args [Array] List of values to be assigned to fields
    # @return [Array<Symbol>] List of field names that were successfully updated
    #   (i.e., had non-nil values assigned)
    # @private
    def initialize_with_positional_args(*args)
      Familia.trace :INITIALIZE_ARGS, nil, args if Familia.debug?
      self.class.fields.zip(args).filter_map do |field, value|
        if value
          send(:"#{field}=", value)
          field.to_sym
        end
      end
    end

    # Initializes the object with keyword arguments.
    # Assigns values to fields based on the provided hash of field names and values.
    # Handles both symbol and string keys to accommodate different sources of data.
    #
    # @param fields [Hash] Hash of field names (as symbols or strings) and their values
    # @return [Array<Symbol>] List of field names that were successfully updated
    #   (i.e., had non-nil values assigned)
    # @private
    def initialize_with_keyword_args(**fields)
      Familia.trace :INITIALIZE_KWARGS, nil, fields.keys if Familia.debug?
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

    # Builds the instance-level connection chain with handlers in priority order
    def build_connection_chain
      Familia::Connection::ResponsibilityChain.new
        .add_handler(Familia::Connection::FiberTransactionHandler.new)
        .add_handler(Familia::Connection::FiberConnectionHandler.new)
        .add_handler(Familia::Connection::ProviderConnectionHandler.new)
        .add_handler(Familia::Connection::DefaultConnectionHandler.new(self))
        .add_handler(Familia::Connection::DefaultConnectionHandler.new(self.class))
        .add_handler(Familia::Connection::CreateConnectionHandler.new(self))
    end
  end
end
