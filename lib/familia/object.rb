require 'ostruct'

module Familia
  require 'familia/redisobject'
  
  # Auto-extended into a class that includes Familia
  module ClassMethods
    
    Familia::RedisObject.registration.each_pair do |kind, klass|
      # e.g. 
      #
      #      list(name, klass, opts)
      #      list?(name)
      #      lists
      #
      define_method :"#{kind}" do |*args, &blk|
        name, opts = *args
        install_redis_object name, klass, opts
        redis_objects[name.to_s.to_sym]
      end
      define_method :"#{kind}?" do |name|
        obj = redis_objects[name.to_s.to_sym]
        !obj.nil? && klass == obj.klass
      end
      define_method :"#{kind}s" do 
        names = redis_objects_order.select { |name| send(:"#{kind}?", name) }
        names.collect! { |name| redis_objects[name] }
        names
      end
      # e.g. 
      #
      #      class_list(name, klass, opts)
      #      class_list?(name)
      #      class_lists
      #
      define_method :"class_#{kind}" do |*args, &blk|
        name, opts = *args
        install_class_redis_object name, klass, opts
      end
      define_method :"class_#{kind}?" do |name|
        obj = class_redis_objects[name.to_s.to_sym]
        !obj.nil? && klass == obj.klass
      end
      define_method :"class_#{kind}s" do 
        names = class_redis_objects_order.select { |name| ret = send(:"class_#{kind}?", name) }
        # TODO: This returns instances of the RedisObject class which
        # also contain the options. This is different from the instance
        # RedisObjects defined above which returns the OpenStruct of name, klass, and opts. 
        #names.collect! { |name| self.send name }
        # OR NOT:
        names.collect! { |name| class_redis_objects[name] }
        names
      end
    end
    
    def inherited(obj)
      obj.db = self.db
      obj.uri = self.uri
      obj.ttl = self.ttl
      obj.parent = self
      obj.class_set :instances
      Familia.classes << obj
      super(obj)
    end
    def extended(obj)
      obj.db = self.db
      obj.ttl = self.ttl
      obj.uri = self.uri
      obj.parent = self
      obj.class_set :instances
      Familia.classes << obj
    end
    
    # Creates an instance method called +name+ that
    # returns an instance of the RedisObject +klass+ 
    def install_redis_object name, klass, opts
      raise ArgumentError, "Name is blank" if name.to_s.empty?
      name = name.to_s.to_sym
      opts ||= {}
      redis_objects_order << name
      redis_objects[name] = OpenStruct.new
      redis_objects[name].name = name
      redis_objects[name].klass = klass
      redis_objects[name].opts = opts
      self.send :attr_reader, name
      define_method "#{name}=" do |v|
        self.send(name).replace v
      end
      redis_objects[name]
    end
    
    # Creates a class method called +name+ that
    # returns an instance of the RedisObject +klass+ 
    def install_class_redis_object name, klass, opts
      raise ArgumentError, "Name is blank" if name.to_s.empty?
      name = name.to_s.to_sym
      opts ||= {}
      opts[:suffix] ||= nil
      opts[:parent] ||= self
      # TODO: investigate using metaclass.redis_objects
      class_redis_objects_order << name
      class_redis_objects[name] = OpenStruct.new
      class_redis_objects[name].name = name
      class_redis_objects[name].klass = klass
      class_redis_objects[name].opts = opts 
      # An accessor method created in the metclass will
      # access the instance variables for this class. 
      metaclass.send :attr_reader, name
      metaclass.send :define_method, "#{name}=" do |v|
        send(name).replace v
      end
      redis_object = klass.new name, opts
      redis_object.freeze
      self.instance_variable_set("@#{name}", redis_object)
      class_redis_objects[name]
    end
    
    def from_redisdump dump
      dump # todo
    end
    attr_accessor :parent
    def ttl v=nil
      @ttl = v unless v.nil?
      @ttl || (parent ? parent.ttl : nil)
    end
    def ttl=(v) @ttl = v end
    def db v=nil
      @db = v unless v.nil?
      @db || (parent ? parent.db : nil)
    end
    def db=(db) @db = db end
    def host(host=nil) @host = host if host; @host end
    def host=(host) @host = host end
    def port(port=nil) @port = port if port; @port end
    def port=(port) @port = port end
    def uri=(uri)
      uri = URI.parse uri if String === uri
      @uri = uri 
    end
    def uri(uri=nil) 
      self.uri = uri unless uri.to_s.empty?
      return @uri if @uri
      @uri = URI.parse Familia.uri.to_s
      @uri.db = @db if @db 
      Familia.connect @uri #unless Familia.connected?(@uri)
      @uri || (parent ? parent.uri : Familia.uri)
    end
    def redis
      Familia.redis(self.uri)
    end
    def flushdb
      Familia.info "flushing #{uri}"
      redis.flushdb
    end
    def keys(suffix=nil)
      self.redis.keys(rediskey('*',suffix)) || []
    end
    def all(suffix=nil)
      # objects that could not be parsed will be nil
      keys(suffix).collect { |k| from_key(k) }.compact 
    end
    def any?(filter='*')
      size(filter) > 0
    end
    def size(filter='*')
      self.redis.keys(rediskey(filter)).compact.size
    end
    def suffix(a=nil, &blk) 
      @suffix = a || blk if a || !blk.nil?
      val = @suffix || Familia.default_suffix
      val
    end
    def prefix=(a) @prefix = a end
    def prefix(a=nil) @prefix = a if a; @prefix || self.name.downcase.to_sym end
    def index(i=nil, &blk) 
      @index = i || blk if i || !blk.nil?
      @index ||= Familia.index
      @index
    end
    def suffixes
      redis_objects.keys.uniq
    end
    def class_redis_objects_order
      @class_redis_objects_order ||= []
      @class_redis_objects_order
    end
    def class_redis_objects
      @class_redis_objects ||= {}
      @class_redis_objects
    end
    def class_redis_objects? name
      class_redis_objects.has_key? name.to_s.to_sym
    end
    def redis_object? name
      redis_objects.has_key? name.to_s.to_sym
    end
    def redis_objects_order
      @redis_objects_order ||= []
      @redis_objects_order
    end
    def redis_objects
      @redis_objects ||= {}
      @redis_objects
    end
    def create(*args)
      me = new(*args)
      raise "#{self} exists: #{me.to_json}" if me.exists?
      me.save
      me
    end
    def load_or_create(id)
      if exists?(id)
        from_redis(id)
      else
        me = new id
        me.save
        me
      end
    end
    
    def multiget(*ids)
      ids = rawmultiget(*ids)
      ids.compact.collect { |json| self.from_json(json) }.compact
    end
    def rawmultiget(*ids)
      ids.collect! { |objid| rediskey(objid) }
      return [] if ids.compact.empty?
      Familia.trace :MULTIGET, self.redis, "#{ids.size}: #{ids}", caller
      ids = self.redis.mget *ids
    end
    
    def from_key(akey)
      raise ArgumentError, "Null key" if akey.nil? || akey.empty?    
      Familia.trace :LOAD, redis, "#{self.uri}/#{akey}", caller if Familia.debug?
      return unless redis.exists akey
      v = redis.get akey
      begin
        if v.to_s.empty?
          Familia.info  "No content @ #{akey}"
          nil
        else
          self.send Familia.load_method, v
        end
      rescue => ex
        Familia.info v
        Familia.info "Non-fatal error parsing JSON for #{akey}: #{ex.message}"
        Familia.info ex.backtrace
        nil
      end
    end
    def from_redis(objid)
      objid &&= objid.to_s
      return nil if objid.nil? || objid.empty?
      this_key = rediskey(objid, self.suffix)
      me = from_key(this_key)
      me
    end
    def exists?(objid, suffix=nil)
      objid &&= objid.to_s
      return false if objid.nil? || objid.empty?
      ret = Familia.redis(self.uri).exists rediskey(objid, suffix)
      Familia.trace :EXISTS, Familia.redis(self.uri), "#{rediskey(objid)} #{ret}", caller.first
      ret
    end
    def destroy!(idx, suffix=nil)  # TODO: remove suffix arg
      ret = Familia.redis(self.uri).del rediskey(runid, suffix)
      Familia.trace :DELETED, Familia.redis(self.uri), "#{rediskey(runid)}: #{ret}", caller.first
      ret
    end
    def find(suffix='*')
      list = Familia.redis(self.uri).keys(rediskey('*', suffix)) || []
    end
    def rediskey(idx, suffix=nil)
      raise RuntimeError, "No index for #{self}" if idx.to_s.empty?
      idx &&= idx.to_s
      Familia.rediskey(prefix, idx, suffix)
    end
    def expand(short_idx, suffix=self.suffix)
      expand_key = Familia.rediskey(self.prefix, "#{short_idx}*", suffix)
      Familia.trace :EXPAND, Familia.redis(self.uri), expand_key, caller.first
      list = Familia.redis(self.uri).keys expand_key
      case list.size
      when 0
        nil
      when 1 
        matches = list.first.match(/\A#{Familia.rediskey(prefix)}\:(.+?)\:#{suffix}/) || []
        matches[1]
      else
        raise Familia::NonUniqueKey, "Short key returned more than 1 match" 
      end
    end
    ## TODO: Investigate
    ##def float
    ##  Proc.new do |v|
    ##    v.nil? ? 0 : v.to_f
    ##  end
    ##end
  end

  
  module InstanceMethods
    
    # A default initialize method. This will be replaced
    # if a class defines its own initialize method after
    # including Familia. In that case, the replacement
    # must call initialize_redis_objects.
    def initialize *args
      initialize_redis_objects
      super   # call Storable#initialize or equivalent
    end
    
    # This needs to be called in the initialize method of
    # any class that includes Familia. 
    def initialize_redis_objects
      # :object is a special redis object because its reserved
      # for storing the marshaled instance data (e.g. to_json).
      # When it isn't defined explicitly we define it here b/c
      # it's assumed to exist in other places (see #save).
      unless self.class.redis_object? :object
        self.class.string :object, :class => self.class
      end
      
      # Generate instances of each RedisObject. These need to be
      # unique for each instance of this class so they can refer
      # to the index of this specific instance. 
      # i.e. 
      #     familia_object.rediskey              == v1:bone:INDEXVALUE:object
      #     familia_object.redis_object.rediskey == v1:bone:INDEXVALUE:name
      #
      # See RedisObject.install_redis_object
      self.class.redis_objects.each_pair do |name, redis_object_definition|
        klass, opts = redis_object_definition.klass, redis_object_definition.opts
        opts ||= {}
        opts[:parent] ||= self
        redis_object = klass.new name, opts
        redis_object.freeze
        self.instance_variable_set "@#{name}", redis_object
      end
    end
    
    def redis
      self.class.redis
    end
    
    def redisinfo
      info = {
        :db   => self.class.db || 0,
        :key  => rediskey,
        :type => redistype,
        :ttl  => realttl
      }
    end
    def exists?
      Familia.redis(self.class.uri).exists rediskey
    end      
    
    #def rediskeys
    #  self.class.redis_objects.each do |redis_object_definition|
    #    
    #  end
    #end
    
    def allkeys
      # TODO: Use redis_objects instead
      keynames = [rediskey]
      self.class.suffixes.each do |sfx| 
        keynames << rediskey(sfx)
      end
      keynames
    end
    def rediskey(suffix=nil)
      raise Familia::NoIndex, self.class if index.to_s.empty?
      if suffix.nil?
        suffix = self.class.suffix.kind_of?(Proc) ? 
                     self.class.suffix.call(self) : 
                     self.class.suffix
      end
      self.class.rediskey self.index, suffix
    end
    def save
      #Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first
      preprocess if respond_to?(:preprocess)
      self.update_time if self.respond_to?(:update_time)
      ret = self.object.set self               # object is a name reserved by Familia
      unless ret.nil?
        self.class.instances.add index         # use this set instead of Klass.keys
        self.object.update_expiration self.ttl # does nothing unless if not specified
      end
      true
    end
    def destroy!
      ret = self.object.delete
      if Familia.debug?
        Familia.trace :DELETED, Familia.redis(self.class.uri), "#{rediskey}: #{ret}", caller.first
      end
      self.class.instances.rem index if ret > 0
      ret
    end
    def index
      case self.class.index
      when Proc
        self.class.index.call(self)
      when Array
        parts = self.class.index.collect { |meth| 
          unless self.respond_to? meth
            raise NoIndex, "No such method: `#{meth}' for #{self.class}"
          end
          self.send(meth) 
        }
        parts.join Familia.delim
      when Symbol, String
        if self.class.redis_object?(self.class.index.to_sym)
          raise Familia::NoIndex, "Cannot use a RedisObject as an index"
        else
          unless self.respond_to? self.class.index
            raise NoIndex, "No such method: `#{self.class.index}' for #{self.class}"
          end
          self.send( self.class.index)
        end
      else
        raise Familia::NoIndex, self
      end
    end
    def index=(i)
      @index = i
    end
    def expire(ttl=nil)
      ttl ||= self.class.ttl
      Familia.redis(self.class.uri).expire rediskey, ttl.to_i
    end
    def realttl
      Familia.redis(self.class.uri).ttl rediskey
    end
    def ttl=(v)
      @ttl = v.to_i
    end
    def ttl
      @ttl || self.class.ttl
    end
    def raw(suffix=nil)
      suffix ||= :object
      Familia.redis(self.class.uri).get rediskey(suffix)
    end
    def redisuri(suffix=nil)
      u = URI.parse self.class.uri.to_s
      u.db ||= self.class.db.to_s
      u.key = rediskey(suffix)
      u
    end
    def redistype(suffix=nil)
      Familia.redis(self.class.uri).type rediskey(suffix)
    end
    # Finds the shortest available unique key (lower limit of 6)
    def shortid
      len = 6
      loop do
        begin
          self.class.expand(@id.shorten(len))
          break
        rescue Familia::NonUniqueKey
          len += 1
        end
      end
      @id.shorten(len) 
    end
  end
  
end