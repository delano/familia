module Familia
  module RedisTypeMetaprogramming
    def self.included(base)
      base.extend(ClassMethods)
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
      def define_redis_type_methods
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
  end
end
