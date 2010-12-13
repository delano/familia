module Familia::Object
  
  class RedisObject
    
    @klasses = {}
    class << self
      attr_reader :klasses
      # To be called inside every class that inherits RedisObject
      def register(kind, klass)
        klasses[kind] = klass
      end
    end
    
    attr_reader :name, :parent
    def initialize n, p, opts={}
      @name, @parent = n, p
      @opts = opts
      init if respond_to? :init
    end
    
    # returns a redis key based on the parent 
    # object so it will include the proper index.
    def rediskey
      parent.rediskey(name)
    end
    
    def redis
      parent.redis
    end
    
    def update_expiration(ttl=nil)
      ttl ||= @opts[:ttl]
      return unless ttl && ttl.to_i > 0
      #Familia.trace :SET_EXPIRE, Familia.redis(self.class.uri), "#{rediskey} to #{self.ttl}"
      expire ttl.to_i
    end
    
    def move db
      redis.move rediskey, db
    end
    
    def destroy! 
      clear
      # TODO: delete redis objects for this instance
    end
    
    # TODO: rename, renamenx
    
    def type 
      redis.type rediskey
    end
    
    def clear 
      redis.del rediskey
    end
    alias_method :delete, :clear
    
    def exists?
      !size.zero?
    end
    
    def expire sec
      redis.expire rediskey, sec.to_i
    end
    
    def expireat unixtime
      redis.expireat rediskey, unixtime
    end
    
    def to_redis v
      return v unless @opts[:class]
      if v.respond_to? Familia.dump_method
        v.send Familia.dump_method
      else
        Familia.ld "No such method: #{v.class}.#{Familia.dump_method}"
        v
      end
    end
    
    def from_redis v
      return v unless @opts[:class]
      case @opts[:class]
      when String
        v.to_s
      when Fixnum, Float
        @opts[:class].induced_from v
      else
        if @opts[:class].method_defined? Familia.load_method
          @opts[:class].send Familia.load_method, v
        else
          Familia.ld "No such method: #{@opts[:class]}##{Familia.load_method}"
          v
        end
      end
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
      # TODO: test maxlength
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
    alias_method :remove, :delete
    
    def range sidx=0, eidx=-1
      # TODO: handle @opts[:marshal]
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
    
    Familia::Object::RedisObject.register :list, self
  end
  
  class Set < RedisObject
    
    def size
      redis.scard rediskey
    end
    alias_method :length, :size
    
    def << v
      redis.sadd rediskey, to_redis(v)
      self
    end
    alias_method :add, :<<
    
    def members
      # TODO: handle @opts[:marshal]
      redis.smembers rediskey
    end
    alias_method :to_a, :members
    
    def member? v
      redis.sismember rediskey, to_redis(v)
    end
    alias_method :include?, :member?
    
    def delete v
      redis.srem rediskey, to_redis(v)
    end
    
    def intersection *setkeys
      # TODO
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
    
    Familia::Object::RedisObject.register :set, self
  end
  
  class SortedSet < RedisObject
    
    def size
      redis.zcard rediskey
    end
    alias_method :length, :size
    
    # e.g. obj.metrics[VALUE] = SCORE
    def []= v, score
      redis.zadd rediskey, score, to_redis(v)
    end
    alias_method :add, :[]=
    
    def score v
      redis.zscore(rediskey, to_redis(v)).to_f
    end
    
    # rank of member +v+ when ordered lowest to highest (starts at 0)
    def rank v
      redis.zrank(rediskey, to_redis(v)).to_i
    end
    
    # rank of member +v+ when ordered highest to lowest (starts at 0)
    def revrank v
      redis.zrevrank(rediskey, to_redis(v)).to_i
    end
    
    def members opts={}
      range 0, -1, opts
    end
    alias_method :to_a, :members
    
    def membersrev opts={}
      rangerev 0, -1, opts
    end
    
    def range sidx, eidx, opts={}
      opts[:with_scores] = true if opts[:withscores]
      redis.zrange rediskey, sidx, eidx, opts
    end

    def rangerev sidx, eidx, opts={}
      opts[:with_scores] = true if opts[:withscores]
      redis.zrevrange rediskey, sidx, eidx, opts
    end
    
    # e.g. obj.metrics.rangebyscore (now-12.hours), now, :limit => [0, 10]
    def rangebyscore sscore, escore, opts={}
      opts[:with_scores] = true if opts[:withscores]
      redis.zrangebyscore rediskey, sscore, escore, opts
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
    
    Familia::Object::RedisObject.register :zset, self
  end

  class HashKey < RedisObject
    
    def size
      redis.hlen rediskey
    end
    alias_method :length, :size
    
    def []= n, v
      redis.hset rediskey, n, to_redis(v)
    end
    alias_method :store, :[]=
    
    def [] n
      redis.hget rediskey, n
    end
    
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
      redis.hvals rediskey
    end
    
    def all
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
      redis.hmget rediskey, *names.flatten.compact
    end
    
    Familia::Object::RedisObject.register :hash, self
  end
  
  class String < RedisObject
    
    def init
      redis.setnx rediskey, @opts[:default] if @opts[:default]
    end
    
    def size
      to_s.size
    end
    alias_method :length, :size
    
    def value
      redis.get rediskey
    end
    alias_method :to_s, :value
    alias_method :get, :value
    
    def value= v
      redis.set rediskey, to_redis(v)
    end
    alias_method :set, :value=    
    
    def nil?
      value.nil?
    end
    
    Familia::Object::RedisObject.register :string, self
  end
  
  
  class Counter < RedisObject
    
    #Familia::Object::RedisObject.register :counter, self
  end
  
end
