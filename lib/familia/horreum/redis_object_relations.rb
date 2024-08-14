module Familia
  module RedisObjectRelations
    # Creates an instance method called +name+ that
    # returns an instance of the RedisType +klass+
    def attach_instance_redis_object_relation(name, klass, opts)
      Familia.ld "[Attaching instance-level #{name}] #{klass} => (#{self}) #{opts}"
      raise ArgumentError, "Name is blank (#{klass})" if name.to_s.empty?

      name = name.to_s.to_sym
      opts ||= {}

      redis_types[name] = Struct.new(:name, :klass, :opts).new
      redis_types[name].name = name
      redis_types[name].klass = klass
      redis_types[name].opts = opts

      attr_reader name

      define_method :"#{name}=" do |val|
        send(name).replace val
      end
      define_method :"#{name}?" do
        !send(name).empty?
      end

      redis_types[name]
    end

    # Creates a class method called +name+ that
    # returns an instance of the RedisType +klass+
    def attach_class_redis_object_relation(name, klass, opts)
      Familia.ld "[#{self}] Attaching class-level #{name} #{klass} => #{opts}"
      raise ArgumentError, 'Name is blank (klass)' if name.to_s.empty?

      name = name.to_s.to_sym
      opts = opts.nil? ? {} : opts.clone
      opts[:parent] = self unless opts.key?(:parent)

      class_redis_types[name] = Struct.new(:name, :klass, :opts).new
      class_redis_types[name].name = name
      class_redis_types[name].klass = klass
      class_redis_types[name].opts = opts

      # An accessor method created in the metaclass will
      # access the instance variables for this class.
      singleton_class.attr_reader name

      define_singleton_method :"#{name}=" do |v|
        send(name).replace v
      end
      define_singleton_method :"#{name}?" do
        !send(name).empty?
      end

      redis_object = klass.new name, opts
      redis_object.freeze
      instance_variable_set(:"@#{name}", redis_object)

      class_redis_types[name]
    end
  end
end
