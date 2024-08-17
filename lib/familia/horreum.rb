# frozen_string_literal: true

module Familia
  #
  # Horreum: A module for managing Redis-based object storage and relationships
  #
  # Key features:
  # * Provides instance-level access to a single hash in Redis
  # * Includes Familia for class/module level access to Redis types and operations
  # * Uses 'hashkey' to define a Redis hash referred to as "object"
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

    # == Singleton Class Context
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
      # Extends ClassMethods to subclasses and tracks Familia members
      def inherited(member)
        Familia.trace :INHERITED, nil, "Inherited by #{member}", caller if Familia.debug?
        member.extend(ClassMethods)
        member.extend(Features)

        # Tracks all the classes/modules that include Familia. It's
        # 10pm, do you know where you Familia members are?
        Familia.members << member
        super
      end
    end

    # Instance initialization
    # This method sets up the object's state, including Redis-related data
    def initialize(*args, **kwargs)
      Familia.ld "[Horreum] Initializing #{self.class}"
      initialize_relatives

      # If there are positional arguments, they should be the field
      # values in the order they were defined in the implementing class.
      #
      # Handle keyword arguments
      # Fields is a known quantity, so we iterate over it rather than kwargs
      # to ensure that we only set fields that are defined in the class. And
      # to avoid runaways.
      if args.any?
        initialize_with_positional_args(*args)
      elsif kwargs.any?
        initialize_with_keyword_args(**kwargs)
      else
        Familia.ld "[Horreum] #{self.class} initialized with no arguments"
        # If there are no arguments, we need to set the default values
        # for the fields. This is done in the order they were defined.
        # self.class.fields.each do |field|
        #  default = self.class.defaults[field]
        #  send(:"#{field}=", default) if default
        # end
      end

      # Automatically add a 'key' field if it's not already defined
      # This ensures that every object has a unique identifier
      unless self.class.fields.include?(:key)
        # Define the 'key' field for this class
        # This approach allows flexibility in how identifiers are generated
        # while ensuring each object has a consistent way to be referenced
        self.class.field :key # , default: -> { identifier }
      end

      # Implementing classes can define an init method to do any
      # additional initialization. Notice that this is called
      # after the fields are set.
      init if respond_to?(:init)
    end

    # Sets up related Redis objects for the instance
    # This method is crucial for establishing Redis-based relationships
    #
    # This needs to be called in the initialize method.
    #
    def initialize_relatives
      # Generate instances of each RedisType. These need to be
      # unique for each instance of this class so they can piggyback
      # on the specifc index of this instance.
      #
      # i.e.
      #     familia_object.rediskey              == v1:bone:INDEXVALUE:object
      #     familia_object.redis_type.rediskey == v1:bone:INDEXVALUE:name
      #
      # See RedisType.install_redis_type
      self.class.redis_types.each_pair do |name, redis_type_definition|
        klass = redis_type_definition.klass
        opts = redis_type_definition.opts
        Familia.ld "[#{self.class}] initialize_relatives #{name} => #{klass} #{opts.keys}"

        # As a subclass of Familia::Horreum, we add ourselves as the parent
        # automatically. This is what determines the rediskey for RedisType
        # instance and which redis connection.
        #
        #   e.g. If the parent's rediskey is `customer:customer_id:object`
        #     then the rediskey for this RedisType instance will be
        #     `customer:customer_id:name`.
        #
        opts[:parent] = self # unless opts.key(:parent)

        # Instantiate the RedisType object and below we store it in
        # an instance variable.
        redis_type = klass.new name, opts

        # Freezes the redis_type, making it immutable.
        # This ensures the object's state remains consistent and prevents any modifications,
        # safeguarding its integrity and making it thread-safe.
        # Any attempts to change the object after this will raise a FrozenError.
        redis_type.freeze

        # e.g. customer.name  #=> `#<Familia::HashKey:0x0000...>`
        instance_variable_set :"@#{name}", redis_type
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
      Familia.trace :INITIALIZE_ARGS, redis, args, caller(1..1) if Familia.debug?
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
      Familia.trace :INITIALIZE_KWARGS, redis, fields.keys, caller(1..1) if Familia.debug?
      self.class.fields.filter_map do |field|
        # Redis will give us field names as strings back, but internally
        # we use symbols. So we check for both.
        value = fields[field.to_sym] || fields[field.to_s]
        if value
          send(:"#{field}=", value)
          field.to_sym
        end
      end
    end
    private :initialize_with_keyword_args

    # A thin wrapper around the private initialize method that accepts a field
    # hash and refreshes the existing object.
    #
    # This method is part of horreum.rb rather than serialization.rb because it
    # operates solely on the provided values and doesn't query Redis or other
    # external sources. That's why it's called "optimistic" refresh: it assumes
    # the provided values are correct and updates the object accordingly.
    #
    # @see #refresh!
    #
    # @param fields [Hash] A hash of field names and their new values to update
    #   the object with.
    # @return [Array] The list of field names that were updated.
    def optimistic_refresh(**fields)
      Familia.ld "[optimistic_refresh] #{self.class} #{rediskey} #{fields.keys}"
      initialize_with_keyword_args(**fields)
    end

    # Determines the unique identifier for the instance
    # This method is used to generate Redis keys for the object
    def identifier
      definition = self.class.identifier # e.g.
      # When definition is a symbol or string, assume it's an instance method
      # to call on the object to get the unique identifier. When it's a callable
      # object, call it with the object as the argument. When it's an array,
      # call each method in turn and join the results. When it's nil, raise
      # an error
      unique_id = case definition
                  when Symbol, String
                    send(definition)
                  when Proc
                    definition.call(self)
                  when Array
                    Familia.join(definition.map { |method| send(method) })
                  else
                    raise Problem, "Invalid identifier definition: #{definition.inspect}"
                  end

      # If the unique_id is nil, raise an error
      raise Problem, "Identifier is nil for #{self.class}" if unique_id.nil?
      raise Problem, 'Identifier is empty' if unique_id.empty?

      unique_id
    end
  end
end

require_relative 'horreum/class_methods'
require_relative 'horreum/commands'
require_relative 'horreum/serialization'
require_relative 'horreum/settings'
require_relative 'horreum/utils'
