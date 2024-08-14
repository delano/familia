# frozen_string_literal: true

module Familia
  #
  # Differences between Familia::Horreum and Familia::HashKey:
  #
  #   * Horreum is a module, HashKey is a class. When included in a class,
  #     Horreum appears in the list of ancestors without getting involved
  #     in the class hierarchy.
  #   * HashKey is a wrapper around Redis hash operations where every
  #     value change is performed directly on redis; Horreum is a cache
  #     that performs atomic operations on a hash in redis (via HashKey).
  #
  # Differences between Familia and Familia::Horreum:
  #
  #   * Familia provides class/module level access to redis types and
  #     operations; Horreum provides instance-level access to a single
  #     hash in redis.
  #   * Horreum includes Familia and uses `hashkey` to define a redis
  #     has that it refers to as simply "object".
  #   * Horreum applies a default expiry to all keys. 5 years. So the
  #     default behaviour is that all data is stored definitely. It also
  #     uses this expiration as the updated timestamp.
  #
  # Horreum is equivalent to Onetime::RedisHash.
  #
  class Horreum
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
      def inherited(member)
        Familia.trace :INHERITED, nil, "Inherited by #{member}", caller if Familia.debug?
        member.extend(ClassMethods)

        # Tracks all the classes/modules that include Familia. It's
        # 10pm, do you know where you Familia members are?
        Familia.members << member
        super
      end
    end

    # A default initialize method. This will be replaced
    # if a class defines its own initialize method after
    # including Familia. In that case, the replacement
    # must call initialize_relatives.
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
        Familia.debug "[Horreum] #{self.class} initialized with no arguments"
      end

      # Implementing classes can define an init method to do any
      # additional initialization. Notice that this is called
      # after the fields are set.
      init if respond_to?(:init)
    end

    def initialize_with_positional_args(*args)
      self.class.fields.zip(args).each do |field, value|
        send(:"#{field}=", value) if value
      end
    end
    private :initialize_with_positional_args

    def initialize_with_keyword_args(**kwargs)
      self.class.fields.each do |field|
        # Redis will give us field names as strings back, but internally
        # we use symbols. So we do both.
        value = kwargs[field.to_sym] || kwargs[field.to_s]
        send(:"#{field}=", value) if value
      end
    end
    private :initialize_with_keyword_args

    # This needs to be called in the initialize method of
    # any class that includes Familia.
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
        Familia.ld "[#{self.class}] initialize_relatives #{name} => #{redis_type_definition.to_a}"
        klass = redis_type_definition.klass
        opts = redis_type_definition.opts

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
      raise Problem, 'Identifier is nil' if unique_id.nil?
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
