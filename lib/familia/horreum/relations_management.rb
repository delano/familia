module Familia
  class Horreum
    # RedisTypeManagement
    #
    # This module encapsulates the functionality for managing Redis-type fields
    # and relations as a distinct feature of the system.
    #
    # Key points:
    # - Feature Encapsulation: Treats Redis Type Field and Relation Management
    #   as a cohesive, self-contained capability.
    # - Implementation Independence: The core functionality (defining and managing
    #   Redis-type fields and relations) is separated from its implementation details.
    # - Interface vs Implementation: Provides a clear public interface, hiding
    #   implementation specifics (such as metaprogramming) from the rest of the system.
    #
    # This approach allows for:
    # - Improved modularity and maintainability
    # - Easier future modifications to the implementation without affecting dependent parts
    # - Clear separation between the feature's interface and its internal workings
    #
    # Usage:
    #   include RedisTypeManagement in classes that need this functionality.
    #   Call setup_redis_type_management to initialize the feature.
    #
    module RelationsManagement
      def self.included(base)
        base.extend(ClassMethods)
        base.setup_relations_management
      end

      module ClassMethods
        # Metaprogramming to add the class-level methods used when defining new
        # familia classes (e.g. classes that `include Familia`). Every class in
        # types/ will have one or more of these methods.
        #
        # e.g. set, list, class_counter etc. are all defined here.
        #
        # NOTE: The term `name` means different things here vs in
        # Onetime::RedisHash. Here it means `Object#name` the string
        # name of the current class. In Onetime::RedisHash it means
        # the name of the redis key.
        #
        def setup_relations_management
          Familia::RedisType.registered_types.each_pair do |kind, klass|
            Familia.ld "[registered_types] #{kind} => #{klass}"

            # Once defined, these methods can be used at the class-level of a
            # Familia member to define *instance-level* relations to any of the
            # RedisType types (e.g. set, list, hash, etc).
            #
            define_method :"#{kind}" do |*args|
              name, opts = *args
              attach_instance_redis_object_relation name, klass, opts
              redis_types[name.to_s.to_sym]
            end
            define_method :"#{kind}?" do |name|
              obj = redis_types[name.to_s.to_sym]
              !obj.nil? && klass == obj.klass
            end
            define_method :"#{kind}s" do
              names = redis_types.keys.select { |name| send(:"#{kind}?", name) }
              names.collect! { |name| redis_types[name] }
              names
            end

            # Once defined, these methods can be used at the class-level of a
            # Familia member to define *class-level relations* to any of the
            # RedisType types (e.g. class_set, class_list, class_hash, etc).
            #
            define_method :"class_#{kind}" do |*args|
              name, opts = *args
              attach_class_redis_object_relation name, klass, opts
            end
            define_method :"class_#{kind}?" do |name|
              obj = class_redis_types[name.to_s.to_sym]
              !obj.nil? && klass == obj.klass
            end
            define_method :"class_#{kind}s" do
              names = class_redis_types.keys.select { |name| send(:"class_#{kind}?", name) }
              # TODO: This returns instances of the RedisType class which
              # also contain the options. This is different from the instance
              # RedisTypes defined above which returns the Struct of name, klass, and opts.
              # names.collect! { |name| self.send name }
              # OR NOT:
              names.collect! { |name| class_redis_types[name] }
              names
            end
          end
        end
      end

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
end
