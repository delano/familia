

module Familia::Object
  require 'familia/redisobject'

  
  # Auto-extended into a class that includes Familia
  module ClassMethods
    
    # e.g. 
    #
    #      list(klass, name, opts)
    #      list?(name)
    #      lists
    #
    RedisObject.klasses.each_pair do |kind, klass|
      define_method :"#{kind}" do |*args, &blk|
        name, opts = *args
        install_redis_object klass, name, opts
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
    end
    
    def inherited(obj)
      obj.db = self.db
      Familia.classes << obj
      super(obj)
    end
    def extended(obj)
      obj.db = self.db
      Familia.classes << obj
    end
    
    # Creates an instance method called +name+ that
    # returns an instance of the RedisObject +klass+ 
    def install_redis_object klass, name, opts
      self.redis_objects[name] = OpenStruct.new
      self.redis_objects[name].name = name
      self.redis_objects[name].klass = klass
      self.redis_objects[name].opts = opts || {}
      self.send :attr_accessor, name
    end
    
    def from_redisdump dump
      dump # todo
    end
    def db(db=nil) 
      @db = db if db; 
      @db
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
      @uri
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
      self.redis_objects[@suffix] = Familia::Object::String
      val
    end
    def prefix=(a)  @prefix = a end
    def prefix(a=nil) @prefix = a if a; @prefix || self.name.downcase end
    def index(i=nil, &blk) 
      @index = i || blk if i || !blk.nil?
      @index ||= Familia.index
      @index
    end
    def ttl(sec=nil)
      @ttl = sec.to_i unless sec.nil? 
      @ttl
    end
    def suffixes
      redis_objects.keys.uniq
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
      Familia.trace :LOAD, Familia.redis(self.uri), "#{self.uri}/#{akey}", caller if Familia.debug?
      return nil unless Familia.redis(self.uri).exists akey
      raise Familia::Problem, "Null key" if akey.nil? || akey.empty?    
      run_json = Familia.redis(self.uri).get akey
      if run_json.nil? || run_json.empty?
        Familia.info  "No content @ #{akey}" 
        return
      end
      begin
        self.from_json(run_json)
      rescue => ex
        Familia.info "Non-fatal error parsing JSON for #{akey}: #{ex.message}"
        Familia.info run_json
        Familia.info ex.backtrace
        nil
      end
    end
    def from_redis(objid, suffix=nil)
      objid &&= objid.to_s
      return nil if objid.nil? || objid.empty?
      this_key = rediskey(objid, suffix)
      #Familia.ld "Reading key: #{this_key}"
      me = from_key(this_key)
      me.gibbler  # prime the gibbler cache (used to check for changes)
      me
    end
    def exists?(objid, suffix=nil)
      objid &&= objid.to_s
      return false if objid.nil? || objid.empty?
      ret = Familia.redis(self.uri).exists rediskey(objid, suffix)
      Familia.trace :EXISTS, Familia.redis(self.uri), "#{rediskey(objid)} #{ret}", caller.first
      ret
    end
    def destroy!(runid, suffix=nil)
      ret = Familia.redis(self.uri).del rediskey(runid, suffix)
      Familia.trace :DELETED, Familia.redis(self.uri), "#{rediskey(runid)}: #{ret}", caller.first
      ret
    end
    def find(suffix='*')
      list = Familia.redis(self.uri).keys(rediskey('*', suffix)) || []
    end
    def rediskey(runid, suffix=nil)
      suffix ||= self.suffix
      runid ||= ''
      runid &&= runid.to_s
      str = Familia.rediskey(prefix, runid, suffix)
      str
    end
    def expand(short_key, suffix=nil)
      suffix ||= self.suffix
      expand_key = Familia.rediskey(self.prefix, "#{short_key}*", suffix)
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
    
    def initialize *args
      super *args
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
        redis_object = klass.new name, self, opts
        self.send("#{name}=", redis_object)
      end
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
    def destroy!
      ret = Familia.redis(self.class.uri).del rediskey
      if Familia.debug?
        Familia.trace :DELETED, Familia.redis(self.class.uri), "#{rediskey}: #{ret}", caller.first
      end
      ret
    end
    def allkeys
      # TODO: Use redis_objects instead
      keynames = [rediskey]
      self.class.suffixes.each do |sfx| 
        keynames << rediskey(sfx)
      end
      keynames
    end
    def rediskey(suffix=nil)
      raise EmptyIndex, self.class if index.nil? || index.empty?
      if suffix.nil?
        suffix = self.class.suffix.kind_of?(Proc) ? 
                     self.class.suffix.call(self) : 
                     self.class.suffix
      end
      self.class.rediskey self.index, suffix
    end
    def save(force=false)
      Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first
      ## Don't save if there are no changes
      ##return false unless force || self.gibbled? || self.gibbler_cache.nil?
      preprocess if respond_to?(:preprocess)
      self.update_time if self.respond_to?(:update_time)
      ret = Familia.redis(self.class.uri).set rediskey, self.to_json
      unless self.ttl.nil? || self.ttl <= 0
        Familia.trace :SET_EXPIRE, Familia.redis(self.class.uri), "#{rediskey} to #{self.ttl}"
        expire(self.ttl) 
      end
      ret == "OK"
    end
    def index
      if @index.nil?
        self.class.index.kind_of?(Proc) ? 
            self.class.index.call(self) : 
            self.send(self.class.index)
      else
        @index
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