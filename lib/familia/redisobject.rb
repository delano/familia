
module Familia
  
  class RedisObject
    @registration = {}
    @classes = []
    
    # To be called inside every class that inherits RedisObject
    # +meth+ becomes the base for the class and instances methods
    # that are created for the given +klass+ (e.g. Obj.list)
    def RedisObject.register klass, meth
      registration[meth] = klass
    end
    
    def RedisObject.registration
      @registration
    end
    
    def RedisObject.classes
      @classes
    end
    
    @db, @ttl = nil, nil
    class << self
      attr_accessor :parent
      attr_writer :ttl, :classes, :db, :uri
      def ttl v=nil
        @ttl = v unless v.nil?
        @ttl || (parent ? parent.ttl : nil)
      end
      def db v=nil
        @db = v unless v.nil?
        @db || (parent ? parent.db : nil)
      end
      def uri v=nil
        @uri = v unless v.nil?
        @uri || (parent ? parent.uri : Familia.uri)
      end
      def inherited(obj)
        obj.db = self.db
        obj.ttl = self.ttl
        obj.uri = self.uri
        obj.parent = self
        RedisObject.classes << obj
        super(obj)
      end
    end
    
    attr_reader :name, :parent
    attr_writer :redis
    
    # +name+: If parent is set, this will be used as the suffix 
    # for rediskey. Otherwise this becomes the value of the key.
    # If this is an Array, the elements will be joined.
    # 
    # Options:
    #
    # :class => A class that responds to Familia.load_method and 
    # Familia.dump_method. These will be used when loading and
    # saving data from/to redis to unmarshal/marshal the class. 
    #
    # :reference => When true the index of the given value will be
    # stored rather than the marshaled value. This assumes that 
    # the marshaled object is stored at a separate key. When read, 
    # from_redis looks for that separate key and returns the 
    # unmarshaled object. :class must be specified. Default: false. 
    #
    # :extend => Extend this instance with the functionality in an 
    # other module. Literally: "self.extend opts[:extend]".
    #
    # :parent => The Familia object that this redis object belongs
    # to. This can be a class that includes Familia or an instance.
    # 
    # :ttl => the time to live in seconds. When not nil, this will
    # set the redis expire for this key whenever #save is called. 
    # You can also call it explicitly via #update_expiration.
    #
    # :default => the default value (String-only)
    #
    # :db => the redis database to use (ignored if :redis is used).
    #
    # :redis => an instance of Redis.
    #
    # Uses the redis connection of the parent or the value of 
    # opts[:redis] or Familia.redis (in that order).
    def initialize name, opts={}
      @name, @opts = name, opts
      @name = @name.join(Familia.delim) if Array === @name
      Familia.ld [name, opts, caller[0]].inspect
      self.extend @opts[:extend] if Module === @opts[:extend]
      @db = @opts.delete(:db)
      @ttl = @opts.delete(:ttl) 
      @parent = @opts.delete(:parent)
      @redis ||= @opts.delete(:redis)
      init if respond_to? :init
    end
    
    def redis
      return @redis if @redis
      parent? ? parent.redis : Familia.redis(db)
    end
    
    def ttl
      @ttl || self.class.ttl
    end
    
    # Returns the most likely value for db, checking (in this order):
    #   * the value from :class if it's a Familia object
    #   * the value from :parent
    #   * the value self.class.db
    #   * assumes the db is 0
    # 
    # After this is called once, this method will always return the 
    # same value.
    def db 
      return @db if @db
      # Note it's important that we select this value at the last
      # possible moment rather than in initialize b/c the value 
      # could be modified after that but before this is called. 
      if @opts[:class] && @opts[:class].ancestors.member?(Familia)
        @db = @opts[:class].db 
      else
        @db = parent? ? parent.db : self.class.db
      end
      @db ||= 0
      @db
    end
    
    # returns a redis key based on the parent 
    # object so it will include the proper index.
    def rediskey
      parent? ? parent.rediskey(name) : [name].flatten.compact.join(Familia.delim)
    end
    
    def parent?
      Class === parent || Module === parent || parent.kind_of?(Familia)
    end
    
    def update_expiration(ttl=nil)
      ttl ||= @opts[:ttl] || self.class.ttl
      return unless ttl && ttl.to_i > 0
      Familia.info "#{rediskey} to #{ttl}"
      expire ttl.to_i
    end
    
    def move db
      redis.move rediskey, db
    end
        
    # TODO: rename, renamenx
    
    def type 
      redis.type rediskey
    end
    
    def delete 
      redis.del rediskey
    end
    alias_method :clear, :delete
    alias_method :del, :delete
    
    #def destroy! 
    #  clear
    #  # TODO: delete redis objects for this instance
    #end
    
    def exists?
      redis.exists(rediskey) && !size.zero?
    end
    
    def realttl
      redis.ttl rediskey
    end
    
    def expire sec
      redis.expire rediskey, sec.to_i
    end
    
    def expireat unixtime
      redis.expireat rediskey, unixtime
    end
    
    def dump_method
      @opts[:dump_method] || Familia.dump_method
    end
    
    def load_method
      @opts[:load_method] || Familia.load_method
    end
    
    def to_redis v
      return v unless @opts[:class]
      case @opts[:class]
      when String, Fixnum, Float, Gibbler::Digest
        v
      else
        if @opts[:reference] == true
          unless v.respond_to? :index
            raise Familia::Problem, "#{v.class} does not have an index method"
          end
          unless v.kind_of?(Familia)
            raise Familia::Problem, "#{v.class} is not Familia (#{name})"
          end
          v.index
        elsif v.respond_to? dump_method
          v.send dump_method
        else
          raise Familia::Problem, "No such method: #{v.class}.#{dump_method}"
        end
      end
    end
    
    def from_redis v
      return @opts[:default] if v.nil?
      return v unless @opts[:class]
      case @opts[:class]
      when String
        v.to_s
      when Fixnum, Float
        @opts[:class].induced_from v
      else
        if @opts[:reference] == true
          @opts[:class].from_redis v
        else
          if @opts[:class].respond_to? load_method
            @opts[:class].send load_method, v
          else
            raise Familia::Problem, "No such method: #{@opts[:class]}##{load_method}"
          end
        end
      end
    rescue => ex
      Familia.info v
      Familia.info "Parse error for #{rediskey} (#{load_method}): #{ex.message}"
      Familia.info ex.backtrace
      nil
    end 
    
  end
  
  
  class List < RedisObject
    
    def size
      redis.llen rediskey
    end
    alias_method :length, :size
    
    def empty?
      size == 0
    end
    
    def push *values
      values.flatten.compact.each { |v| redis.rpush rediskey, to_redis(v) }
      redis.ltrim rediskey, -@opts[:maxlength], -1 if @opts[:maxlength]
      self
    end
    
    def << v
      push v
    end
    
    def unshift *values
      values.flatten.compact.each { |v| redis.lpush rediskey, to_redis(v) }
      # TODO: test maxlength
      redis.ltrim rediskey, 0, @opts[:maxlength] - 1 if @opts[:maxlength]
      self
    end
    
    def pop
      from_redis redis.rpop(rediskey)
    end
    
    def shift
      from_redis redis.lpop(rediskey)
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
    alias_method :remove, :delete
    alias_method :rem, :delete
    alias_method :del, :delete
    
    def range sidx=0, eidx=-1
      redis.lrange(rediskey, sidx, eidx).collect do |v|
        from_redis v
      end
    end
    
    def members count=-1
      range 0, count
    end
    alias_method :all, :members
    alias_method :to_a, :members
    
    #def revmembers count=1  #TODO
    #  range -count, 0
    #end
    
    def each &blk
      range.each &blk
    end
    
    def each_with_index &blk
      range.each_with_index &blk
    end
    
    def collect &blk
      range.collect &blk
    end
    
    def select &blk
      range.select &blk
    end
    
    def at idx
      from_redis redis.lindex(rediskey, idx)
    end
    
    def first
      at 0
    end

    def last
      at -1
    end
    
    # TODO: def replace
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
    
    Familia::RedisObject.register self, :list
  end
  
  class Set < RedisObject
    
    def size
      redis.scard rediskey
    end
    alias_method :length, :size
    
    def empty?
      size == 0
    end
    
    def add *values
      values.flatten.compact.each { |v| redis.sadd rediskey, to_redis(v) }
      self
    end
    
    def << v
      add v
    end
    
    def members
      redis.smembers(rediskey).collect do |v|
        from_redis v
      end
    end
    alias_method :all, :members
    alias_method :to_a, :members
    
    def each &blk
      members.each &blk
    end
    
    def each_with_index &blk
      members.each_with_index &blk
    end
    
    def collect &blk
      members.collect &blk
    end
    
    def select &blk
      members.select &blk
    end
    
    def member? v
      redis.sismember rediskey, to_redis(v)
    end
    alias_method :include?, :member?
    
    def delete v
      redis.srem rediskey, to_redis(v)
    end
    alias_method :rem, :delete
    alias_method :del, :delete
    
    def intersection *setkeys
      # TODO
    end
    
    def pop
      redis.spop rediskey
    end
    
    def move dstkey, v
      redis.smove rediskey, dstkey, v
    end
    
    def random
      from_redis redis.srandmember(rediskey)
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
    
    Familia::RedisObject.register self, :set
  end
  
  class SortedSet < RedisObject
    
    def size
      redis.zcard rediskey
    end
    alias_method :length, :size
    
    def empty?
      size == 0
    end
    
    # NOTE: The argument order is the reverse of #add
    # e.g. obj.metrics[VALUE] = SCORE
    def []= v, score
      add score, v
    end
    
    # NOTE: The argument order is the reverse of #[]=
    def add score, v
      redis.zadd rediskey, score, to_redis(v)
    end
    
    def score v
      ret = redis.zscore rediskey, to_redis(v)
      ret.nil? ? nil : ret.to_f
    end
    alias_method :[], :score
    
    def member? v
      !rank(v).nil?
    end
    alias_method :include?, :member?
    
    # rank of member +v+ when ordered lowest to highest (starts at 0)
    def rank v
      ret = redis.zrank rediskey, to_redis(v)
      ret.nil? ? nil : ret.to_i
    end
    
    # rank of member +v+ when ordered highest to lowest (starts at 0)
    def revrank v
      ret = redis.zrevrank rediskey, to_redis(v)
      ret.nil? ? nil : ret.to_i
    end
    
    def members count=-1, opts={}
      range 0, count, opts
    end
    alias_method :to_a, :members
    alias_method :all, :members
    
    def revmembers count=-1, opts={}
      revrange 0, count, opts
    end
    
    def each &blk
      members.each &blk
    end

    def each_with_index &blk
      members.each_with_index &blk
    end
    
    def collect &blk
      members.collect &blk
    end
    
    def select &blk
      members.select &blk
    end
    
    def range sidx, eidx, opts={}
      opts[:with_scores] = true if opts[:withscores]
      redis.zrange(rediskey, sidx, eidx, opts).collect do |v|
        from_redis v
      end
    end

    def revrange sidx, eidx, opts={}
      opts[:with_scores] = true if opts[:withscores]
      redis.zrevrange(rediskey, sidx, eidx, opts).collect do |v|
        from_redis v
      end
    end
    
    # e.g. obj.metrics.rangebyscore (now-12.hours), now, :limit => [0, 10]
    def rangebyscore sscore, escore, opts={}
      opts[:with_scores] = true if opts[:withscores]
      redis.zrangebyscore(rediskey, sscore, escore, opts).collect do |v|
        from_redis v
      end
    end
    
    def remrangebyrank srank, erank
      redis.zremrangebyrank rediskey, srank, erank
    end

    def remrangebyscore sscore, escore
      redis.zremrangebyscore rediskey, sscore, escore
    end
    
    def increment v, by=1
      redis.zincrby(rediskey, by, v).to_i
    end
    alias_method :incr, :increment
    alias_method :incrby, :increment

    def decrement v, by=1
      increment v, -by
    end
    alias_method :decr, :decrement
    alias_method :decrby, :decrement
    
    def delete v
      redis.zrem rediskey, to_redis(v)
    end
    alias_method :remove, :delete
    alias_method :rem, :delete
    alias_method :del, :delete
      
    def at idx
      range(idx, idx).first
    end

    # Return the first element in the list. Redis: ZRANGE(0)
    def first
      at(0)
    end

    # Return the last element in the list. Redis: ZRANGE(-1)
    def last
      at(-1)
    end
    
    Familia::RedisObject.register self, :zset
  end

  class HashKey < RedisObject
    
    def size
      redis.hlen rediskey
    end
    alias_method :length, :size
    
    def empty?
      size == 0
    end
    
    def []= n, v
      redis.hset rediskey, n, to_redis(v)
    end
    alias_method :put, :[]=
    alias_method :store, :[]=
    
    def [] n
      from_redis redis.hget(rediskey, n)
    end
    alias_method :get, :[]
    
    def fetch n, default=nil
      ret = self[n]
      if ret.nil? 
        raise IndexError.new("No such index for: #{n}") if default.nil?
        default
      else
        ret
      end
    end
    
    def keys
      redis.hkeys rediskey
    end
    
    def values
      redis.hvals(rediskey).collect do |v|
        from_redis v
      end
    end
    
    def all
      # TODO: from_redis
      redis.hgetall rediskey
    end
    alias_method :to_hash, :all
    alias_method :clone, :all
    
    def has_key? n
      redis.hexists rediskey, n
    end
    alias_method :include?, :has_key?
    alias_method :member?, :has_key?
    
    def delete n
      redis.hdel rediskey, n
    end
    alias_method :remove, :delete
    alias_method :rem, :delete
    alias_method :del, :delete
    
    def increment n, by=1
      redis.hincrby(rediskey, n, by).to_i
    end
    alias_method :incr, :increment
    alias_method :incrby, :increment
    
    def decrement n, by=1
      increment n, -by
    end
    alias_method :decr, :decrement
    alias_method :decrby, :decrement
    
    def update h={}
      raise ArgumentError, "Argument to bulk_set must be a hash" unless Hash === h
      redis.hmset(rediskey, h.inject([]){ |ret,pair| ret + [pair[0], to_redis(pair[1])] })
    end
    alias_method :merge!, :update
    
    def values_at *names
      redis.hmget(rediskey, *names.flatten.compact).collect do |v|
        from_redis v
      end
    end
    
    Familia::RedisObject.register self, :hash
  end
  
  class String < RedisObject
    
    def init
    end
    
    def size
      to_s.size
    end
    alias_method :length, :size
    
    def empty?
      size == 0
    end
    
    def value
      redis.setnx rediskey, @opts[:default] if @opts[:default]
      from_redis redis.get(rediskey)
    end
    alias_method :content, :value
    alias_method :get, :value
    
    def to_s
      value.to_s  # value can return nil which to_s should not
    end
    
    def to_i
      value.to_i
    end
    
    def value= v
      redis.set rediskey, to_redis(v)
    end
    alias_method :replace, :value=
    alias_method :set, :value=  
    
    def increment
      redis.incr rediskey
    end
    alias_method :incr, :increment

    def incrementby int
      redis.incrby rediskey, int.to_i
    end
    alias_method :incrby, :incrementby

    def decrement
      redis.decr rediskey
    end
    alias_method :decr, :decrement

    def decrementby int
      redis.decrby rediskey, int.to_i
    end
    alias_method :decrby, :decrementby
    
    def append v
      redis.append rediskey, v
    end
    alias_method :<<, :append

    def getbit offset
      redis.getbit rediskey, offset
    end

    def setbit offset, v
      redis.setbit rediskey, offset, v
    end

    def getrange spoint, epoint
      redis.getrange rediskey, spoint, epoint
    end

    def setrange offset, v
      redis.setrange rediskey, offset, v
    end
    
    def getset v
      redis.getset rediskey, v
    end
    
    def nil?
      value.nil?
    end
    
    Familia::RedisObject.register self, :string
  end
  
end

