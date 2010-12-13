

module Familia::Object
  
  module InstanceMethods
    
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
      self.class.redis_objects.each_pair do |name, redis_object_class|
        redis_object = redis_object_class.new name, self
        self.send("#{name}=", redis_object)
      end
    end
  end
  
  # Auto-extended into a class that includes Familia
  module ClassMethods
    def inherited(obj)
      obj.db = self.db
      Familia.classes << obj
      super(obj)
    end
    def extended(obj)
      obj.db = self.db
      Familia.classes << obj
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
    def suffix=(val)   
      suffixes << (@suffix = val)
      val
    end
    def suffix(a=nil, &blk) 
      @suffix = a || blk if a || !blk.nil?
      val = @suffix || Familia.default_suffix
      self.suffixes << val
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
      @suffixes ||= []
      @suffixes.uniq!
      @suffixes
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
  
  class RedisObject
    
    # Auto-extended into a class that includes Familia
    module ClassMethods
      
      def string(name, opts={}, &blk)
        strings[name] = opts[:class]
        install_redis_object Familia::Object::String, name
      end
      def string?(name)
        strings.has_key? name.to_s.to_sym
      end
      def strings
        @strings ||= {}
        @strings
      end

      def hash(name, opts={}, &blk)
        hashes[name] = opts[:class]
        install_redis_object Familia::Object::HashKey, name
      end
      def hashes
        @hashes ||= {}
        @hashes
      end
      def hash?(name)
        @hashes.has_key? name.to_s.to_sym
      end

      def set(name, opts={}, &blk)
        sets[name] = opts[:class]
        install_redis_object Familia::Object::Set, name
      end
      def sets
        @sets ||= {}
        @sets
      end
      def set?(name)
        sets.has_key? :"#{name}"
      end

      def zset(name, opts={}, &blk)
        zsets[name] = opts[:class]
        install_redis_object Familia::Object::SortedSet, name
      end
      def zsets
        @zsets ||= {}
        @zsets
      end
      def zset?(name)
        zsets.has_key? :"#{name}"
      end

      def list(name, opts={}, &blk)
        lists[name] = opts[:class]
        install_redis_object Familia::Object::List, name
      end
      def lists
        @lists ||= {}
        @lists
      end
      def list?(name)
        lists.has_key? :"#{name}"
      end
      
      # Creates an instance method called +name+ that
      # returns an instance of the RedisObject +klass+ 
      def install_redis_object klass, name
        self.suffixes << name
        self.redis_objects[name] = klass
        self.send :attr_accessor, name
      end
    end
    
    attr_reader :name, :parent
    def initialize n, p, opts={}
      @name, @parent = n, p
      @opts = {}
    end
    
    # returns a redis key based on the parent 
    # object so it will include the proper index.
    def rediskey
      parent.rediskey(name)
    end
    
    def redis
      parent.class.redis
    end
    
    def destroy! 
      redis.del rediskey
    end
    
    def exists?
      !size.zero?
    end
    
    def to_redis v
      return v unless @opts[:dump]
      RedisObject.dump v, @opts[:class]
    end
    
    def from_redis v
      return v unless @opts[:dump]
      RedisObject.load v, @opts[:class]
    end
    
    def RedisObject.dump(v, klass)
      case v
      when String, Fixnum, Bignum, Float
        v
      else
        # TODO: dump to JSON
        v
      end
    end
    
    def RedisObject.load(v, klass)
      v # TODO: load from JSON, including Fixnum, Bignum, Float
    end
    
  end
  
  
  class List < RedisObject
    
    def size
      redis.llen rediskey
    end
    alias_method :length, :size
    
    def << v
      redis.rpush rediskey, to_redis(v)
      redis.ltrim rediskey, -@opts[:maxlength], -1 if @opts[:maxlength]
      self
    end
    alias_method :push, :<<

    def unshift v
      redis.lpush rediskey, to_redis(v)
      redis.ltrim rediskey, 0, @opts[:maxlength] - 1 if @opts[:maxlength]
      self
    end
    
    def pop
      from_redis redis.rpop(rediskey)
    end
    
    def shift
      from_redis redis.lpop(key)
    end
    
    def [] idx, count=nil
      if idx.is_a? Range
        range idx.first, idx.last
      elsif count
        case count <=> 0
        when 1  then range(idx, idx + count - 1)
        when 0  then []
        when -1 then nil
        end
      else
        at idx
      end
    end
    alias_method :slice, :[]
    
    def delete v, count=0
      redis.lrem rediskey, count, to_redis(v)
    end
    
    def range sidx=0, eidx=-1
      redis.lrange rediskey, sidx, eidx
    end
    alias_method :to_a, :range
    
    def at idx
      from_redis redis.lindex(rediskey, idx)
    end
    
    def first
      at 0
    end

    def last
      at -1
    end
    
    ## Make the value stored at KEY identical to the given list
    #define_method :"#{name}_sync" do |*latest|
    #  latest = latest.flatten.compact
    #  # Do nothing if we're given an empty Array. 
    #  # Otherwise this would clear all current values
    #  if latest.empty?
    #    false
    #  else
    #    # Convert to a list of index values if we got the actual objects
    #    latest = latest.collect { |obj| obj.index } if klass === latest.first
    #    current = send("#{name_plural}raw")
    #    added = latest-current
    #    removed = current-latest
    #    #Familia.info "#{self.index}: adding: #{added}"
    #    added.each { |v| self.send("add_#{name_singular}", v) }
    #    #Familia.info "#{self.index}: removing: #{removed}"
    #    removed.each { |v| self.send("remove_#{name_singular}", v) }
    #    true
    #  end
    #end
    #define_method :"#{name}?" do
    #  self.send(:"#{name}_size") > 0
    #end
    #define_method :"add_#{name_singular}" do |obj|
    #  objid = klass === obj ? obj.index : obj
    #  #Familia.ld "#{self.class} Add #{objid} to #{key(name)}"
    #  ret = self.class.redis.rpush key(name), objid
    #  # TODO : copy to zset and set
    #  #unless self.ttl.nil? || self.ttl <= 0
    #  #  Familia.trace :SET_EXPIRE, Familia.redis(self.class.uri), "#{self.key} to #{self.ttl}"
    #  #  Familia.redis(self.class.uri).expire key(name), self.ttl
    #  #end
    #  ret
    #end
    #define_method :"remove_#{name_singular}" do |obj|
    #  objid = klass === obj ? obj.index : obj
    #  #Familia.ld "#{self.class} Remove #{objid} from #{key(name)}"
    #  self.class.redis.lrem key(name), 0, objid
    #end
    #define_method :"#{name_plural}raw" do |*args|
    #  count = args.first-1 unless args.empty?
    #  count ||= -1
    #  list = self.class.redis.lrange(key(name), 0, count) || []
    #end
    #define_method :"#{name_plural}" do |*args|
    #  list = send("#{name_plural}raw", *args)
    #  if klass.nil? 
    #    list 
    #  elsif klass.include?(Familia) 
    #    klass.multiget(*list)
    #  elsif klass.respond_to?(:from_json)
    #    list.collect { |str| klass.from_json(str) }
    #  else
    #    list
    #  end
    #end
  end
  
  class Set < RedisObject
    
    #define_method :"#{name}_key" do
    #  key(name)
    #end
    #define_method :"#{name}_size" do
    #  self.class.redis.scard key(name)
    #end
    ## Make the value stored at KEY identical to the given list
    #define_method :"#{name}_sync" do |*latest|
    #  latest = latest.flatten.compact
    #  # Do nothing if we're given an empty Array. 
    #  # Otherwise this would clear all current values
    #  if latest.empty?
    #    false
    #  else
    #    # Convert to a list of index values if we got the actual objects
    #    latest = latest.collect { |obj| obj.index } if klass === latest.first
    #    current = send("#{name_plural}raw")
    #    added = latest-current
    #    removed = current-latest
    #    #Familia.info "#{self.index}: adding: #{added}"
    #    added.each { |v| self.send("add_#{name_singular}", v) }
    #    #Familia.info "#{self.index}: removing: #{removed}"
    #    removed.each { |v| self.send("remove_#{name_singular}", v) }
    #    true
    #  end
    #end
    #define_method :"#{name}?" do
    #  self.send(:"#{name}_size") > 0
    #end
    #define_method :"clear_#{name}" do
    #  self.class.redis.del key(name)
    #end
    #define_method :"add_#{name_singular}" do |obj|
    #  objid = klass === obj ? obj.index : obj
    #  #Familia.ld "#{self.class} Add #{objid} to #{key(name)}"
    #  self.class.redis.sadd key(name), objid
    #end
    #define_method :"remove_#{name_singular}" do |obj|
    #  objid = klass === obj ? obj.index : obj
    #  #Familia.ld "#{self.class} Remove #{objid} from #{key(name)}"
    #  self.class.redis.srem key(name), objid
    #end
    ## Example:
    ##
    ##     list = obj.response_time 10, :score => (now-12.hours)..now
    ##
    #define_method :"#{name_plural}raw" do 
    #  list = self.class.redis.smembers(key(name)) || []
    #end
    #define_method :"#{name_plural}" do 
    #  list = send("#{name_plural}raw")
    #  if klass.nil? 
    #    list 
    #  elsif klass.include?(Familia) 
    #    klass.multiget(*list)
    #  elsif klass.respond_to?(:from_json)
    #    list.collect { |str| klass.from_json(str) }
    #  else
    #    list
    #  end
    #end
  end
  
  class SortedSet < RedisObject
    #define_method :"#{name}_key" do
    #  key(name)
    #end
    #define_method :"#{name}_size" do
    #  self.class.redis.zcard key(name)
    #end
    #define_method :"clear_#{name}" do
    #  self.class.redis.del key(name)
    #end
    #define_method :"#{name}?" do
    #  self.send(:"#{name}_size") > 0
    #end
    #define_method :"add_#{name_singular}" do |score,obj|
    #  objid = klass === obj ? obj.index : obj
    #  #Familia.ld "#{self.class} Add #{objid} (#{score}) to #{key(name)}"
    #  self.class.redis.zadd key(name), score, objid
    #end
    ##p "Adding: #{self}#remove_#{name_singular}"
    #define_method :"remove_#{name_singular}" do |obj|
    #  objid = klass === obj ? obj.index : obj
    #  #Familia.ld "#{self.class} Remove #{objid} from #{key(name)}"
    #  self.class.redis.zrem key(name), objid
    #end
    ## Example:
    ##
    ##     list = obj.response_time 10, :score => (now-12.hours)..now
    ##
    #define_method :"#{name_plural}raw" do |*args|
    #  
    #  count = args.first-1 unless args.empty?
    #  count ||= -1
    #  
    #  opts = args[1] || {}
    #  if Range === opts[:score]
    #    lo, hi = opts[:score].first, opts[:score].last
    #    list = self.class.redis.zrangebyscore(key(name), lo, hi, :limit => [0, count]) || []
    #  else                       
    #    list = self.class.redis.zrange(key(name), 0, count) || []
    #  end
    #end
    #define_method :"#{name_plural}" do |*args|
    #  list = send("#{name_plural}raw", *args)
    #  if klass.nil? 
    #    list 
    #  elsif klass.include?(Familia) 
    #    klass.multiget(*list)
    #  elsif klass.respond_to?(:from_json)
    #    list.collect { |str| klass.from_json(str) }
    #  else
    #    list
    #  end
    #end
    #define_method :"#{name_plural}rev" do |*args|
    #  
    #  count = args.first-1 unless args.empty?
    #  count ||= -1
    #  
    #  opts = args[1] || {}
    #  if Range === opts[:score]
    #    lo, hi = opts[:score].first, opts[:score].last
    #    list = self.class.redis.zrangebyscore(key(name), lo, hi, :limit => [0, count]) || []
    #  else                       
    #    list = self.class.redis.zrevrange(key(name), 0, count) || []
    #  end
    #  if klass.nil? 
    #    list 
    #  elsif klass.include?(Familia) 
    #    klass.multiget(*list)
    #  elsif klass.respond_to?(:from_json)
    #    list.collect { |str| klass.from_json(str) }
    #  else
    #    list
    #  end
    #end
  end

  class HashKey < RedisObject
    #define_method :"#{name}_key" do
    #  key(name)
    #end
    #define_method :"has_#{name}?" do |field|
    #  self.class.redis.hexists key(name), field
    #end
    #define_method :"#{name}_size" do 
    #  self.class.redis.hlen key(name)
    #end
    #define_method :"clear_#{name}" do
    #  self.class.redis.del key(name)
    #end
    #define_method :"#{name}_keys" do 
    #  self.class.redis.hkeys key(name)
    #end
    #define_method :"set_#{name}" do |hash|
    #  self.class.redis.hmset key(name), *hash.to_a.flatten
    #end
    #define_method :"get_#{name}" do |*fields|
    #  ret = self.class.redis.hmget key(name), *fields
    #  ret.collect! { |obj| blk.call(obj) } if blk
    #  fields.size == 1 ? ret.first : ret
    #end
    #define_method :"del_#{name}" do |field|
    #  self.class.redis.hdel key(name), field
    #end
  end

  class String < RedisObject
    
    #define_method :"#{name}_key" do
    #  key(name)
    #end
    #define_method :"#{name}?" do
    #  #Familia.ld "EXISTS? #{self.class.strings[name]} #{key(name)}"
    #  self.class.strings[name].redis.exists key(name)
    #end
    #define_method :"clear_#{name}" do
    #  self.class.redis.del key(name)
    #end
    #define_method :"#{name}" do
    #  #Familia.ld "#{self.class} Return string #{key(name)}"
    #  content = self.class.redis.get key(name)
    #  #Familia.ld "TODO: don't reload #{self.class} every time"
    #  if !content.nil?
    #    begin
    #      content = self.class.strings[name].from_json content if klass != String && content.is_a?(String)
    #    rescue => ex
    #      msg = "Error loading #{name} for #{key}: #{ex.message}"
    #      Familia.info "#{msg}: #{$/}#{content}"
    #      raise Familia::Problem, msg
    #    end
    #  else
    #    content = self.class.strings[name].new
    #  end
    #  content
    #end
    #define_method :"#{name}=" do |content|
    #  Familia.ld "#{self.class} Modify string #{key(name)} (#{content.class})"
    #  self.class.redis.set key(name), (content.is_a?(String) ? content : content.to_json)
    #  content
    #end
  end


  class Counter < RedisObject
  end
  
end