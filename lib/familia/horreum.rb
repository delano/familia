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
    # must call initialize_redis_objects.
    def initialize *args, **kwargs
      Familia.ld "[Horreum] Initializing #{self.class} with arguments (#{args.inspect}, #{kwargs.inspect})"
      initialize_redis_objects

      # if args is not empty, it contains the values for the fields in the order
      # they were defined in the class. This is the only way to set the fields
      # when initializing a new object.
      #
      args.each_with_index do |value, index|
        field = self.class.fields[index]
        p [8, field, value]
        send(:"#{field}=", value)
      end

      # Handle keyword arguments
      # Fields is a known quantity, so we iterate over it rather than kwargs
      # to ensure that we only set fields that are defined in the class. And
      # to avoid runaways.
      self.class.fields.each do |field|
        field_sym = field.to_sym
        # Redis will give us field names as strings back, but internally
        # we use symbols. So we convert the field name to a symbol.
        next unless kwargs.key?(field_sym) || kwargs.key?(field_sym.to_s)

        value = kwargs[field_sym] || kwargs[field_sym.to_s]
        p [9, field, value]
        send(:"#{field}=", value)
      end

      # Check if the class has an init method and call it if it does.
      init(*args) if respond_to? :init
    end

    # This needs to be called in the initialize method of
    # any class that includes Familia.
    def initialize_redis_objects
      # Generate instances of each RedisType. These need to be
      # unique for each instance of this class so they can piggyback
      # on the specifc index of this instance.
      #
      # i.e.
      #     familia_object.rediskey              == v1:bone:INDEXVALUE:object
      #     familia_object.redis_object.rediskey == v1:bone:INDEXVALUE:name
      #
      # See RedisType.install_redis_object
      self.class.redis_objects.each_pair do |name, redis_object_definition|
        Familia.ld "[#{self.class}] initialize_redis_objects #{name} => #{redis_object_definition.to_a}"
        klass = redis_object_definition.klass
        opts = redis_object_definition.opts

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
        redis_object = klass.new name, opts

        # Freezes the redis_object, making it immutable.
        # This ensures the object's state remains consistent and prevents any modifications,
        # safeguarding its integrity and making it thread-safe.
        # Any attempts to change the object after this will raise a FrozenError.
        redis_object.freeze

        # e.g. customer.name  #=> `#<Familia::HashKey:0x0000...>`
        instance_variable_set :"@#{name}", redis_object
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

    def redis
      self.class.redis
    end
  end
end

require_relative 'horreum/class_methods'
require_relative 'horreum/commands'
require_relative 'horreum/serialization'
require_relative 'horreum/settings'
require_relative 'horreum/utils'
