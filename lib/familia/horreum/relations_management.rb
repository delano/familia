module Familia
  class Horreum
    #
    # RelationsManagement: Manages Redis-type fields and relations
    #
    # This module uses metaprogramming to dynamically create methods
    # for managing different types of Redis objects (e.g., sets, lists, hashes).
    #
    # Key metaprogramming features:
    # * Dynamically defines methods for each Redis type (e.g., set, list, hashkey)
    # * Creates both instance-level and class-level relation methods
    # * Provides query methods for checking relation types
    #
    # Usage:
    #   Include this module in classes that need Redis-type management
    #   Call setup_relations_accessors to initialize the feature
    #
    module RelationsManagement
      def self.included(base)
        base.extend(ClassMethods)
        base.setup_relations_accessors
      end

      module ClassMethods
        # Sets up all Redis-type related methods
        # This method is the core of the metaprogramming logic
        #
        def setup_relations_accessors
          Familia::RedisType.registered_types.each_pair do |kind, klass|
            Familia.ld "[registered_types] #{kind} => #{klass}"

            # Dynamically define instance-level relation methods
            #
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

            # Dynamically define class-level relation methods
            #
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
      # End of ClassMethods module

      # Creates an instance-level relation
      def attach_instance_redis_object_relation(name, klass, opts)
        Familia.ld "[#{self}##{name}] Attaching instance-level #{klass} #{opts}"
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

      # Creates a class-level relation
      def attach_class_redis_object_relation(name, klass, opts)
        Familia.ld "[#{self}.#{name}] Attaching class-level #{klass} #{opts}"
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
    # End of RelationsManagement module
  end
end
