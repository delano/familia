# rubocop:disable all

require 'attic'


module Familia
  # ClassMethods - Module containing class-level methods for Familia
  #
  # This module is extended into classes that include Familia, providing
  # class-level functionality for Redis operations and object management.
  #
  class Horreum
    module ClassMethods
      # NOTE: The term `name` means different things here vs in
      # Onetime::RedisHash. Here it means `Object#name` the string
      # name of the current class. In Onetime::RedisHash it means
      # the name of the redis key.
      #

      Familia.ld "[Familia::RedisObject::ClassMethods] add_methods #{Familia::RedisObject.registration}"

      Familia::RedisObject.registration.each_pair do |kind, klass|
        Familia.ld "[registration] #{kind} => #{klass}"

        # e.g.
        #
        #      list(name, klass, opts)
        #      list?(name)
        #      lists
        #
        define_method :"#{kind}" do |*args|
          name, opts = *args
          attach_instance_redis_object_relation name, klass, opts
          redis_objects[name.to_s.to_sym]
        end
        define_method :"#{kind}?" do |name|
          obj = redis_objects[name.to_s.to_sym]
          !obj.nil? && klass == obj.klass
        end
        define_method :"#{kind}s" do
          names = redis_objects.keys.select { |name| send(:"#{kind}?", name) }
          names.collect! { |name| redis_objects[name] }
          names
        end

        # e.g.
        #
        #      class_list(name, klass, opts)
        #      class_list?(name)
        #      class_lists
        #
        define_method :"class_#{kind}" do |*args|
          name, opts = *args
          attach_class_redis_object_relation name, klass, opts
        end
        define_method :"class_#{kind}?" do |name|
          obj = class_redis_objects[name.to_s.to_sym]
          !obj.nil? && klass == obj.klass
        end
        define_method :"class_#{kind}s" do
          names = class_redis_objects.keys.select { |name| send(:"class_#{kind}?", name) }
          # TODO: This returns instances of the RedisObject class which
          # also contain the options. This is different from the instance
          # RedisObjects defined above which returns the Struct of name, klass, and opts.
          # names.collect! { |name| self.send name }
          # OR NOT:
          names.collect! { |name| class_redis_objects[name] }
          names
        end
      end

      def inherited(obj)
        Familia.ld "[#{self}] inherited by [#{obj}] (superclass: #{obj.superclass}, #{defined?(super)})"
        obj.db = db
        obj.uri = uri
        obj.ttl = ttl
        obj.parent = self
        obj.class_zset :instances, class: obj, reference: true
        Familia.classes << obj
        super(obj)
      end

      def extended(obj)
        Familia.ld "[#{self}] extended by [#{obj}] (superclass: #{obj.superclass}, #{defined?(super)})"
        obj.db = db
        obj.ttl = ttl
        obj.uri = uri
        obj.parent = self
        obj.class_zset :instances, class: obj, reference: true
        Familia.classes << obj
      end

      # Creates an instance method called +name+ that
      # returns an instance of the RedisObject +klass+
      def attach_instance_redis_object_relation(name, klass, opts)
        Familia.ld "[Attaching instance-level #{name}] #{klass} => #{opts}"
        raise ArgumentError, "Name is blank (#{klass})" if name.to_s.empty?

        name = name.to_s.to_sym
        opts ||= {}
        redis_objects[name] = Struct.new(:name, :klass, :opts).new
        redis_objects[name].name = name
        redis_objects[name].klass = klass
        redis_objects[name].opts = opts

        attr_reader name

        define_method "#{name}=" do |val|
          send(name).replace val
        end
        define_method "#{name}?" do
          !send(name).empty?
        end
        redis_objects[name]
      end

      # Creates a class method called +name+ that
      # returns an instance of the RedisObject +klass+
      def attach_class_redis_object_relation(name, klass, opts)
        Familia.ld "[Attaching class-level #{name}] #{klass} => #{opts}"
        raise ArgumentError, 'Name is blank (klass)' if name.to_s.empty?

        name = name.to_s.to_sym
        opts = opts.nil? ? {} : opts.clone
        opts[:parent] = self unless opts.has_key?(:parent)
        # TODO: investigate using attic.redis_objects
        class_redis_objects[name] = Struct.new(:name, :klass, :opts).new
        class_redis_objects[name].name = name
        class_redis_objects[name].klass = klass
        class_redis_objects[name].opts = opts
        # An accessor method created in the metclass will
        # access the instance variables for this class.
        superclass.send :attr_reader, name
        superclass.send :define_method, "#{name}=" do |v|
          send(name).replace v
        end
        superclass.send :define_method, "#{name}?" do
          !send(name).empty?
        end

        redis_object = klass.new name, opts
        redis_object.freeze
        instance_variable_set("@#{name}", redis_object)

        class_redis_objects[name]
      end

      def from_redisdump(dump)
        dump # todo
      end
      attr_accessor :parent

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

      def ttl=(v)
        @ttl = v
      end

      def db(v = nil)
        @db = v unless v.nil?
        @db || (parent ? parent.db : nil)
      end

      def db=(db)
        @db = db
      end

      def host(host = nil)
        @host = host if host
        @host
      end

      def host=(host)
        @host = host
      end

      def port(port = nil)
        @port = port if port
        @port
      end

      def port=(port)
        @port = port
      end

      def uri=(uri)
        uri = URI.parse uri if uri.is_a?(String)
        @uri = uri
      end

      def uri(uri = nil)
        self.uri = uri unless uri.to_s.empty?
        @uri ||= (parent ? parent.uri : Familia.uri)
        @uri.db = @db if @db && @uri.db.to_s != @db.to_s
        @uri
      end

      def redis
        Familia.redis uri
      end

      def flushdb
        Familia.info "flushing #{uri}"
        redis.flushdb
      end

      def keys(suffix = nil)
        redis.keys(rediskey('*', suffix)) || []
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

      def prefix=(a)
        @prefix = a
      end

      def prefix(a = nil)
        @prefix = a if a
        @prefix || name.downcase.gsub('::', Familia.delim).to_sym
      end

      # TODO: grab db, ttl, uri from parent
      # def parent=(a) @parent = a end
      # def parent(a=nil) @parent = a if a; @parent end
      def index(i = nil, &blk)
        @index = i || blk if i || !blk.nil?
        @index ||= Familia.index
        @index
      end

      def suffixes
        redis_objects.keys.uniq
      end

      def class_redis_objects
        @class_redis_objects ||= {}
        @class_redis_objects
      end

      def class_redis_objects?(name)
        class_redis_objects.has_key? name.to_s.to_sym
      end

      def redis_object?(name)
        redis_objects.has_key? name.to_s.to_sym
      end

      def redis_objects
        @redis_objects ||= {}
        @redis_objects
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

      # Returns an instance based on +idx+ otherwise it
      # creates and saves a new instance base on +idx+.
      # See from_index
      def load_or_create(idx)
        return from_redis(idx) if exists?(idx)

        obj = from_index idx
        obj.save
        obj
      end

      # Note +idx+ needs to be an appropriate index for
      # the given class. If the index is multi-value it
      # must be passed as an Array in the proper order.
      # Does not call save.
      def from_index(idx)
        obj = new
        obj.index = idx
        obj
      end

      def from_key(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        Familia.trace :LOAD, Familia.redis(uri), objkey, caller if Familia.debug?
        obj = Familia::String.new objkey, class: self
        obj.value
      end

      def from_redis(idx, suffix = :object)
        return nil if idx.to_s.empty?

        objkey = rediskey idx, suffix
        # Familia.trace :FROMREDIS, Familia.redis(self.uri), objkey, caller.first if Familia.debug?
        from_key objkey
      end

      def exists?(idx, suffix = :object)
        return false if idx.to_s.empty?

        objkey = rediskey idx, suffix
        ret = Familia.redis(uri).exists objkey
        Familia.trace :EXISTS, Familia.redis(uri), "#{rediskey(idx, suffix)} #{ret}", caller if Familia.debug?
        ret
      end

      def destroy!(idx, suffix = :object)
        ret = Familia.redis(uri).del rediskey(idx, suffix)
        Familia.trace :DELETED, Familia.redis(uri), "#{rediskey(idx, suffix)}: #{ret}", caller if Familia.debug?
        ret
      end

      def find(suffix = '*')
        Familia.redis(uri).keys(rediskey('*', suffix)) || []
      end

      # idx can be a value or an Array of values used to create the index.
      # We don't enforce a default suffix; that's left up to the instance.
      # A nil +suffix+ will not be included in the key.
      def rediskey(idx, suffix = self.suffix)
        raise "No index for #{self}" if idx.to_s.empty?

        idx = Familia.join(*idx) if idx.is_a?(Array)
        idx &&= idx.to_s
        Familia.rediskey(prefix, idx, suffix)
      end

      def expand(short_idx, suffix = self.suffix)
        expand_key = Familia.rediskey(prefix, "#{short_idx}*", suffix)
        Familia.trace :EXPAND, Familia.redis(uri), expand_key, caller.first if Familia.debug?
        list = Familia.redis(uri).keys expand_key
        case list.size
        when 0
          nil
        when 1
          matches = list.first.match(/\A#{Familia.rediskey(prefix)}:(.+?):#{suffix}/) || []
          matches[1]
        else
          raise Familia::NonUniqueKey, 'Short key returned more than 1 match'
        end
      end
    end

  end
end
