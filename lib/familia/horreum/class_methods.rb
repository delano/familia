# rubocop:disable all




module Familia
  # ClassMethods - Module containing class-level methods for Familia
  #
  # This module is extended into classes that include Familia, providing
  # class-level functionality for Redis operations and object management.
  #
  class Horreum
    module ClassMethods
      include Familia::Settings

      attr_accessor :parent
      attr_writer :redis, :dump_method, :load_method

      def redis
        @redis || Familia.redis(uri)
      end

      # The object field or instance method to call to get the unique identifier
      # for that instance. The value returned by this method will be used to
      # generate the key for the object in Redis.
      def identifier(val = nil)
        @identifier = val if val
        @identifier
      end

      # Define a field for the class. This will create getter and setter
      # instance methods just like any "attr_accessor" methods.
      def field(name)
        fields << name
        attr_accessor name
      end

      # Returns the list of field names defined for the class in the order
      # that they were defined. i.e. `field :a; field :b; fields => [:a, :b]`.
      def fields
        @fields ||= []
        @fields
      end

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
        define_method :"class_#{kind}" do |*args|
          name, opts = *args # e.g. `class_set :name, {ttl: 10.minutes}`
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
        define_method "#{name}?" do
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

        define_singleton_method "#{name}=" do |v|
          send(name).replace v
        end
        define_singleton_method "#{name}?" do
          !send(name).empty?
        end

        redis_object = klass.new name, opts
        redis_object.freeze
        instance_variable_set("@#{name}", redis_object)

        class_redis_types[name]
      end

      def qstamp(quantum = nil, pattern = nil, now = Familia.now)
        quantum ||= ttl || 10.minutes
        pattern ||= '%H%M'
        rounded = now - (now % quantum)
        Time.at(rounded).utc.strftime(pattern)
      end

      def ttl(v = nil)
        @ttl = v unless v.nil?
        @ttl || (parent ? parent.ttl : nil)
      end

      def db(v = nil)
        @db = v unless v.nil?
        @db || (parent ? parent.db : nil)
      end

      def uri(v = nil)
        @uri = v unless v.nil?
        @uri || (parent ? parent.uri : nil)
      end

      def all(suffix = :object)
        # objects that could not be parsed will be nil
        keys(suffix).collect { |k| from_key(k) }.compact
      end

      def any?(filter = '*')
        size(filter) > 0
      end

      def size(filter = '*')
        redis.keys(rediskey(filter)).compact.size
      end

      def suffix(a = nil, &blk)
        @suffix = a || blk if a || !blk.nil?
        @suffix || Familia.default_suffix
      end

      def prefix(a = nil)
        @prefix = a if a
        @prefix || name.downcase.gsub('::', Familia.delim).to_sym
      end

      def class_redis_types
        @class_redis_types ||= {}
        @class_redis_types
      end

      def class_redis_types?(name)
        class_redis_types.has_key? name.to_s.to_sym
      end

      def redis_object?(name)
        redis_types.has_key? name.to_s.to_sym
      end

      def redis_types
        @redis_types ||= {}
        @redis_types
      end

      def defined_fields
        @defined_fields ||= {}
        @defined_fields
      end

      def create *args
        me = from_array(*args)
        raise "#{self} exists: #{me.rediskey}" if me.exists?

        me.save
        me
      end

      def multiget(*ids)
        ids = rawmultiget(*ids)
        ids.compact.collect { |json| from_json(json) }.compact
      end

      def rawmultiget(*ids)
        ids.collect! { |objid| rediskey(objid) }
        return [] if ids.compact.empty?

        Familia.trace :MULTIGET, redis, "#{ids.size}: #{ids}", caller if Familia.debug?
        redis.mget(*ids)
      end

      def from_key(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        Familia.ld "[.from_key] #{self} from key #{objkey})"
        Familia.trace :LOAD, Familia.redis(uri), objkey, caller if Familia.debug?
        obj = redis.hgetall(objkey) # horreum objects are saved as redis hashes
        self.new(**obj)
      end

      #
      # TODO: Needs a lot of work since it's used in a bunch of places. Just eneds to be more grokable.
      #
      def from_redis(identifier, suffix = :object)
        return nil if identifier.to_s.empty?

        objkey = rediskey(identifier, suffix)
        Familia.ld "[.from_redis] #{self} from key #{objkey})"
        # Familia.trace :FROMREDIS, Familia.redis(self.uri), objkey, caller.first if Familia.debug?
        from_key objkey
      end

      def exists?(identifier, suffix = :object)
        return false if identifier.to_s.empty?

        objkey = rediskey identifier, suffix
        ret = Familia.redis(uri).exists objkey
        Familia.trace :EXISTS, Familia.redis(uri), "#{rediskey(identifier, suffix)} #{ret}", caller if Familia.debug?
        ret
      end

      def destroy!(identifier, suffix = :object)
        ret = Familia.redis(uri).del rediskey(identifier, suffix)
        Familia.trace :DELETED, Familia.redis(uri), "#{rediskey(identifier, suffix)}: #{ret}", caller if Familia.debug?
        ret
      end

      def find(suffix = '*')
        Familia.redis(uri).keys(rediskey('*', suffix)) || []
      end

      # +identifier+ can be a value or an Array of values used to create the index.
      # We don't enforce a default suffix; that's left up to the instance.
      # The suffix is used to differentiate between different types of objects.
      #
      #
      # A nil +suffix+ will not be included in the key.
      def rediskey(identifier, suffix = self.suffix)
        Familia.ld "[.rediskey] #{identifier} for #{self} (suffix:#{suffix})"
        raise NoIdentifier, self if identifier.to_s.empty?
        identifier &&= identifier.to_s
        Familia.rediskey(prefix, identifier, suffix)
      end

      def dump_method
        @dump_method || :to_json # Familia.dump_method
      end

      def load_method
        @load_method || :from_json # Familia.load_method
      end
    end

  end
end
