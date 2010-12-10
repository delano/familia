# encoding: utf-8
FAMILIA_LIB_HOME = File.expand_path File.dirname(__FILE__) unless defined?(FAMILIA_LIB_HOME)
require 'uri/redis'

module Familia
  module VERSION
    def self.to_s
      load_config
      [@version[:MAJOR], @version[:MINOR], @version[:PATCH]].join('.')
    end
    alias_method :inspect, :to_s
    def self.load_config
      require 'yaml'
      @version ||= YAML.load_file(File.join(FAMILIA_LIB_HOME, '..', 'VERSION.yml'))
    end
  end
end


module Familia
  include Gibbler::Complex
  @secret = '1-800-AWESOME' # Should be modified via Familia.secret = ''
  @clients = {}
  @conf = {}
  @suffix = :object.freeze
  @index = :id.freeze
  @apiversion = nil
  @uri = URI.parse 'redis://localhost'
  @debug = false.freeze
  @classes = []
  @delim = ':'
  class << self
    attr_reader :conf, :classes, :clients
    attr_accessor :debug, :secret, :delim
    def debug?() @debug == true end
  end
  class Problem < RuntimeError; end
  class EmptyIndex < Problem; end
  class NonUniqueKey < Problem; end
  class NotConnected < Problem
    attr_reader :uri
    def initialize uri
      @uri = uri
    end
    def message
      "No client for #{uri.serverid}"
    end
  end
  def Familia.uri(db=nil)
    if db.nil?
      @uri
    else
      uri = URI.parse @uri.to_s
      uri.db = db
      uri
    end
  end
  def Familia.apiversion(r=nil, &blk)  
    if blk.nil?
      @apiversion = r if r; 
    else
      tmp = @apiversion
      @apiversion = r
      blk.call
      @apiversion = tmp
    end
    @apiversion 
  end
  def Familia.apiversion=(r) @apiversion = r; r end
  def Familia.conf=(conf={})
    @conf = conf
    @uri = Redis.uri(@conf).freeze
    connect @uri
    @conf
  end
  def Familia.redis(uri=nil)
    uri &&= URI.parse uri if String === uri
    uri ||= Familia.uri
    connect(uri) unless @clients[uri.serverid] 
    #STDERR.puts "REDIS: #{uri} #{caller[0]}" if Familia.debug?
    @clients[uri.serverid]
  end
  def Familia.connect(uri=nil, local_conf={})
    uri &&= URI.parse uri if String === uri
    uri ||= Familia.uri
    local_conf[:thread_safe] = true
    client = Redis.new local_conf.merge(uri.conf)
    Familia.trace :CONNECT, client, uri.conf.inspect, caller.first
    @clients[uri.serverid] = client
  end
  def Familia.reconnect_all!
    Familia.classes.each do |klass|
      klass.redis.client.reconnect
      Familia.info "#{klass} ping: #{klass.redis.ping}" if debug?
    end
  end
  def Familia.connected?(uri=nil)
    uri &&= URI.parse uri if String === uri
    @clients.has_key?(uri.serverid)
  end
  def Familia.default_suffix(a=nil) @suffix = a if a; @suffix end
  def Familia.default_suffix=(a) @suffix = a end
  def Familia.index(r=nil)  @index = r if r; @index end
  def Familia.index=(r) @index = r; r end
  def Familia.split(r) r.split(Familia.delim) end
  def Familia.key *args
    el = args.flatten.compact
    el.unshift @apiversion unless @apiversion.nil?
    el.join(Familia.delim)
  end
  def Familia.info *msg
    STDERR.puts *msg
  end
  def Familia.ld *msg
    info *msg if debug?
  end
  def Familia.trace label, redis_client, ident, context=nil
    return unless Familia.debug?
    info "%s (%d:%s): %s" % [label, Thread.current.object_id, redis_client.object_id, ident] 
    info "  +-> %s" % [context].flatten[0..3].join("\n      ") if context
  end
  def Familia.destroy keyname, uri=nil
    Familia.redis(uri).del keyname
  end
  def Familia.get_any keyname, uri=nil
    type = Familia.redis(uri).type keyname
    case type
    when "string"
      Familia.redis(uri).get keyname
    when "list"
      Familia.redis(uri).lrange(keyname, 0, -1) || []
    when "set"
      Familia.redis(uri).smembers( keyname) || []
    when "zset"
      Familia.redis(uri).zrange(keyname, 0, -1) || []
    when "hash"
      Familia.redis(uri).hgetall(keyname) || {}
    else
      nil
    end
  end
  def Familia.exists?(keyname, uri=nil)
    Familia.redis(uri).exists keyname
  end
  
  def self.included(obj)
    obj.send :include, Familia::InstanceMethods
    obj.send :include, Gibbler::Complex
    obj.extend  Familia::ClassMethods
    Familia.classes << obj
  end
  
  module InstanceMethods
    def redisinfo
      info = {
        :db   => self.class.db || 0,
        #:uri  => redisuri,
        :key  => key,
        :type => redistype,
        :ttl  => realttl
      }
    end
    def exists?
      Familia.redis(self.class.uri).exists self.key
    end
    def destroy!(suffix=nil)
      ret = Familia.redis(self.class.uri).del self.key(suffix)
      Familia.trace :DELETED, Familia.redis(self.class.uri), "#{key(suffix)}: #{ret}", caller.first
      ret
    end
    def allkeys
      keynames = [key]
      self.class.suffixes.each do |sfx| 
        keynames << key(sfx)
      end
      keynames
    end
    def key(suffix=nil)
      raise EmptyIndex, self.class if index.nil? || index.empty?
      if suffix.nil?
        suffix = self.class.suffix.kind_of?(Proc) ? 
                     self.class.suffix.call(self) : 
                     self.class.suffix
      end
      self.class.key self.index, suffix
    end
    def save(force=false)
      Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first
      ## Don't save if there are no changes
      ##return false unless force || self.gibbled? || self.gibbler_cache.nil?
      preprocess if respond_to?(:preprocess)
      self.update_time if self.respond_to?(:update_time)
      ret = Familia.redis(self.class.uri).set self.key, self.to_json
      unless self.ttl.nil? || self.ttl <= 0
        Familia.trace :SET_EXPIRE, Familia.redis(self.class.uri), "#{self.key} to #{self.ttl}"
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
      Familia.redis(self.class.uri).expire self.key, ttl.to_i
    end
    def realttl
      Familia.redis(self.class.uri).ttl self.key
    end
    def ttl=(v)
      @ttl = v.to_i
    end
    def ttl
      @ttl || self.class.ttl
    end
    def raw(suffix=nil)
      suffix ||= :object
      Familia.redis(self.class.uri).get key(suffix)
    end
    def redisuri(suffix=nil)
      u = URI.parse self.class.uri.to_s
      u.db ||= self.class.db.to_s
      u.key = key(suffix)
      u
    end
    def redistype(suffix=nil)
      Familia.redis(self.class.uri).type key(suffix)
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
  
  module ClassMethods
    def inherited(obj)
      obj.db = self.db
      Familia.classes << obj
      super(obj)
    end
    def from_redisdump dump
      dump
    end
    def float
      Proc.new do |v|
        v.nil? ? 0 : v.to_f
      end
    end
    def extended(obj)
      obj.db = self.db
      Familia.classes << obj
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
      self.redis.keys(key('*',suffix)) || []
    end
    def all(suffix=nil)
      # objects that could not be parsed will be nil
      keys(suffix).collect { |k| from_key(k) }.compact 
    end
    def any?(filter='*')
      size(filter) > 0
    end
    def size(filter='*')
      self.redis.keys(key(filter)).compact.size
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
    def suffixes
      @suffixes ||= []
      @suffixes.uniq!
      @suffixes
    end
    def child(opts={})
      name, klass = opts.keys.first, opts.values.first
      childs[name] = klass
      self.suffixes << name
      define_method :"#{name}_key" do
        key(name)
      end
      define_method :"#{name}?" do
        #Familia.ld "EXISTS? #{self.class.childs[name]} #{key(name)}"
        self.class.childs[name].redis.exists key(name)
      end
      define_method :"clear_#{name}" do
        self.class.redis.del key(name)
      end
      define_method :"#{name}" do
        #Familia.ld "#{self.class} Return child #{key(name)}"
        content = self.class.redis.get key(name)
        #Familia.ld "TODO: don't reload #{self.class} every time"
        if !content.nil?
          begin
            content = self.class.childs[name].from_json content if klass != String && content.is_a?(String)
          rescue => ex
            msg = "Error loading #{name} for #{key}: #{ex.message}"
            Familia.info "#{msg}: #{$/}#{content}"
            raise Familia::Problem, msg
          end
        else
          content = self.class.childs[name].new
        end
        content
      end
      define_method :"#{name}=" do |content|
        Familia.ld "#{self.class} Modify child #{key(name)} (#{content.class})"
        self.class.redis.set key(name), (content.is_a?(String) ? content : content.to_json)
        content
      end
    end
    def child?(name)
      childs.has_key? :"#{name}"
    end
    def childs
      @childs ||= {}
      @childs
    end
    def hashes
      @hashes ||= {}
      @hashes
    end
    def hash?(name)
      @hashes.has_key? :"#{name}"
    end
    def hash(opts={}, &blk)
      if Hash === opts
        name, klass = opts.keys.first, opts.values.first
      else
        name, klass = opts, nil
      end
      hashes[name] = klass
      self.suffixes << name
      if name.to_s.match(/s$/i)
        name_plural = name.to_s.clone
        name_singular = name.to_s[0..-2]
      else
        name_plural = "#{name}s"
        name_singular = name
      end
      define_method :"#{name}_key" do
        key(name)
      end
      define_method :"has_#{name}?" do |field|
        self.class.redis.hexists key(name), field
      end
      define_method :"#{name}_size" do 
        self.class.redis.hlen key(name)
      end
      define_method :"clear_#{name}" do
        self.class.redis.del key(name)
      end
      define_method :"#{name}_keys" do 
        self.class.redis.hkeys key(name)
      end
      define_method :"set_#{name}" do |hash|
        self.class.redis.hmset key(name), *hash.to_a.flatten
      end
      define_method :"get_#{name}" do |*fields|
        ret = self.class.redis.hmget key(name), *fields
        ret.collect! { |obj| blk.call(obj) } if blk
        fields.size == 1 ? ret.first : ret
      end
      define_method :"del_#{name}" do |field|
        self.class.redis.hdel key(name), field
      end
    end
    
    def sets
      @sets ||= {}
      @sets
    end
    def set?(name)
      sets.has_key? :"#{name}"
    end
    def set(opts={})
      if Hash === opts
        name, klass = opts.keys.first, opts.values.first
      else
        name, klass = opts, nil
      end
      sets[name] = klass
      self.suffixes << name
      if name.to_s.match(/s$/i)
        name_plural = name.to_s.clone
        name_singular = name.to_s[0..-2]
      else
        name_plural = "#{name}s"
        name_singular = name
      end
      define_method :"#{name}_key" do
        key(name)
      end
      define_method :"#{name}_size" do
        self.class.redis.scard key(name)
      end
      # Make the value stored at KEY identical to the given list
      define_method :"#{name}_sync" do |*latest|
        latest = latest.flatten.compact
        # Do nothing if we're given an empty Array. 
        # Otherwise this would clear all current values
        if latest.empty?
          false
        else
          # Convert to a list of index values if we got the actual objects
          latest = latest.collect { |obj| obj.index } if klass === latest.first
          current = send("#{name_plural}raw")
          added = latest-current
          removed = current-latest
          #Familia.info "#{self.index}: adding: #{added}"
          added.each { |v| self.send("add_#{name_singular}", v) }
          #Familia.info "#{self.index}: removing: #{removed}"
          removed.each { |v| self.send("remove_#{name_singular}", v) }
          true
        end
      end
      define_method :"#{name}?" do
        self.send(:"#{name}_size") > 0
      end
      define_method :"clear_#{name}" do
        self.class.redis.del key(name)
      end
      define_method :"add_#{name_singular}" do |obj|
        objid = klass === obj ? obj.index : obj
        #Familia.ld "#{self.class} Add #{objid} to #{key(name)}"
        self.class.redis.sadd key(name), objid
      end
      define_method :"remove_#{name_singular}" do |obj|
        objid = klass === obj ? obj.index : obj
        #Familia.ld "#{self.class} Remove #{objid} from #{key(name)}"
        self.class.redis.srem key(name), objid
      end
      # Example:
      #
      #     list = obj.response_time 10, :score => (now-12.hours)..now
      #
      define_method :"#{name_plural}raw" do 
        list = self.class.redis.smembers(key(name)) || []
      end
      define_method :"#{name_plural}" do 
        list = send("#{name_plural}raw")
        if klass.nil? 
          list 
        elsif klass.include?(Familia) 
          klass.multiget(*list)
        elsif klass.respond_to?(:from_json)
          list.collect { |str| klass.from_json(str) }
        else
          list
        end
      end
    end
    def zsets
      @zsets ||= {}
      @zsets
    end
    def zset?(name)
      zsets.has_key? :"#{name}"
    end
    def zset(opts={})
      if Hash === opts
        name, klass = opts.keys.first, opts.values.first
      else
        name, klass = opts, nil
      end
      zsets[name] = klass
      self.suffixes << name
      if name.to_s.match(/s$/i)
        name_plural = name.to_s.clone
        name_singular = name.to_s[0..-2]
      else
        name_plural = "#{name}s"
        name_singular = name
      end
      define_method :"#{name}_key" do
        key(name)
      end
      define_method :"#{name}_size" do
        self.class.redis.zcard key(name)
      end
      define_method :"clear_#{name}" do
        self.class.redis.del key(name)
      end
      define_method :"#{name}?" do
        self.send(:"#{name}_size") > 0
      end
      define_method :"add_#{name_singular}" do |score,obj|
        objid = klass === obj ? obj.index : obj
        #Familia.ld "#{self.class} Add #{objid} (#{score}) to #{key(name)}"
        self.class.redis.zadd key(name), score, objid
      end
      #p "Adding: #{self}#remove_#{name_singular}"
      define_method :"remove_#{name_singular}" do |obj|
        objid = klass === obj ? obj.index : obj
        #Familia.ld "#{self.class} Remove #{objid} from #{key(name)}"
        self.class.redis.zrem key(name), objid
      end
      # Example:
      #
      #     list = obj.response_time 10, :score => (now-12.hours)..now
      #
      define_method :"#{name_plural}raw" do |*args|
        
        count = args.first-1 unless args.empty?
        count ||= -1
        
        opts = args[1] || {}
        if Range === opts[:score]
          lo, hi = opts[:score].first, opts[:score].last
          list = self.class.redis.zrangebyscore(key(name), lo, hi, :limit => [0, count]) || []
        else                       
          list = self.class.redis.zrange(key(name), 0, count) || []
        end
      end
      define_method :"#{name_plural}" do |*args|
        list = send("#{name_plural}raw", *args)
        if klass.nil? 
          list 
        elsif klass.include?(Familia) 
          klass.multiget(*list)
        elsif klass.respond_to?(:from_json)
          list.collect { |str| klass.from_json(str) }
        else
          list
        end
      end
      define_method :"#{name_plural}rev" do |*args|
        
        count = args.first-1 unless args.empty?
        count ||= -1
        
        opts = args[1] || {}
        if Range === opts[:score]
          lo, hi = opts[:score].first, opts[:score].last
          list = self.class.redis.zrangebyscore(key(name), lo, hi, :limit => [0, count]) || []
        else                       
          list = self.class.redis.zrevrange(key(name), 0, count) || []
        end
        if klass.nil? 
          list 
        elsif klass.include?(Familia) 
          klass.multiget(*list)
        elsif klass.respond_to?(:from_json)
          list.collect { |str| klass.from_json(str) }
        else
          list
        end
      end
    end

    def list(opts={})
      if Hash === opts
        name, klass = opts.keys.first, opts.values.first
      else
        name, klass = opts, nil
      end
      lists[name] = klass
      self.suffixes << name
      if name.to_s.match(/s$/i)
        name_plural = name.to_s.clone
        name_singular = name.to_s[0..-2]
      else
        name_plural = "#{name}s"
        name_singular = name
      end
      define_method :"#{name}_key" do
        key(name)
      end
      define_method :"#{name}_size" do
        self.class.redis.llen key(name)
      end
      define_method :"clear_#{name}" do
        self.class.redis.del key(name)
      end
      # Make the value stored at KEY identical to the given list
      define_method :"#{name}_sync" do |*latest|
        latest = latest.flatten.compact
        # Do nothing if we're given an empty Array. 
        # Otherwise this would clear all current values
        if latest.empty?
          false
        else
          # Convert to a list of index values if we got the actual objects
          latest = latest.collect { |obj| obj.index } if klass === latest.first
          current = send("#{name_plural}raw")
          added = latest-current
          removed = current-latest
          #Familia.info "#{self.index}: adding: #{added}"
          added.each { |v| self.send("add_#{name_singular}", v) }
          #Familia.info "#{self.index}: removing: #{removed}"
          removed.each { |v| self.send("remove_#{name_singular}", v) }
          true
        end
      end
      define_method :"#{name}?" do
        self.send(:"#{name}_size") > 0
      end
      define_method :"add_#{name_singular}" do |obj|
        objid = klass === obj ? obj.index : obj
        #Familia.ld "#{self.class} Add #{objid} to #{key(name)}"
        ret = self.class.redis.rpush key(name), objid
        # TODO : copy to zset and set
        #unless self.ttl.nil? || self.ttl <= 0
        #  Familia.trace :SET_EXPIRE, Familia.redis(self.class.uri), "#{self.key} to #{self.ttl}"
        #  Familia.redis(self.class.uri).expire key(name), self.ttl
        #end
        ret
      end
      define_method :"remove_#{name_singular}" do |obj|
        objid = klass === obj ? obj.index : obj
        #Familia.ld "#{self.class} Remove #{objid} from #{key(name)}"
        self.class.redis.lrem key(name), 0, objid
      end
      define_method :"#{name_plural}raw" do |*args|
        count = args.first-1 unless args.empty?
        count ||= -1
        list = self.class.redis.lrange(key(name), 0, count) || []
      end
      define_method :"#{name_plural}" do |*args|
        list = send("#{name_plural}raw", *args)
        if klass.nil? 
          list 
        elsif klass.include?(Familia) 
          klass.multiget(*list)
        elsif klass.respond_to?(:from_json)
          list.collect { |str| klass.from_json(str) }
        else
          list
        end
      end
    end
    def lists
      @lists ||= {}
      @lists
    end
    def list?(name)
      lists.has_key? :"#{name}"
    end
    def multiget(*ids)
      ids = rawmultiget(*ids)
      ids.compact.collect { |json| self.from_json(json) }.compact
    end
    def rawmultiget(*ids)
      ids.collect! { |objid| self.key(objid) }
      return [] if ids.compact.empty?
      Familia.trace :MULTIGET, self.redis, "#{ids.size}: #{ids}", caller
      ids = self.redis.mget *ids
    end
    def ttl(sec=nil)
      @ttl = sec.to_i unless sec.nil? 
      @ttl
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
    def from_key(akey)
      Familia.trace :LOAD, Familia.redis(self.uri), "#{self.uri}/#{akey}", caller
      return nil unless Familia.redis(self.uri).exists akey
      raise Familia::Problem, "Null key" if akey.nil? || akey.empty?    
      run_json = Familia.redis(self.uri).get akey
      if run_json.nil? || run_json.empty?
        Familia.info  "No content @ #{akey}" 
        return
      end
      begin
        #run_json.force_encoding("ASCII-8BIT") if RUBY_VERSION >= "1.9"
        obj = self.from_json(run_json)
        obj
      rescue => ex
        STDOUT.puts "Non-fatal error parsing JSON for #{akey}: #{ex.message}"
        STDOUT.puts run_json
        STDERR.puts ex.backtrace
        nil
      end
    end
    def from_redis(objid, suffix=nil)
      objid &&= objid.to_s
      return nil if objid.nil? || objid.empty?
      this_key = key(objid, suffix)
      #Familia.ld "Reading key: #{this_key}"
      me = from_key(this_key)
      me.gibbler  # prime the gibbler cache (used to check for changes)
      me
    end
    def exists?(objid, suffix=nil)
      objid &&= objid.to_s
      return false if objid.nil? || objid.empty?
      ret = Familia.redis(self.uri).exists key(objid, suffix)
      Familia.trace :EXISTS, Familia.redis(self.uri), "#{key(objid)} #{ret}", caller.first
      ret
    end
    def destroy!(runid, suffix=nil)
      ret = Familia.redis(self.uri).del key(runid, suffix)
      Familia.trace :DELETED, Familia.redis(self.uri), "#{key(runid)}: #{ret}", caller.first
      ret
    end
    def find(suffix='*')
      list = Familia.redis(self.uri).keys(key('*', suffix)) || []
    end
    def key(runid, suffix=nil)
      suffix ||= self.suffix
      runid ||= ''
      runid &&= runid.to_s
      str = Familia.key(prefix, runid, suffix)
      str
    end
    def expand(short_key, suffix=nil)
      suffix ||= self.suffix
      expand_key = Familia.key(self.prefix, "#{short_key}*", suffix)
      Familia.trace :EXPAND, Familia.redis(self.uri), expand_key, caller.first
      list = Familia.redis(self.uri).keys expand_key
      case list.size
      when 0
        nil
      when 1 
        matches = list.first.match(/\A#{Familia.key(prefix)}\:(.+?)\:#{suffix}/) || []
        matches[1]
      else
        raise Familia::NonUniqueKey, "Short key returned more than 1 match" 
      end
    end
  end
end

module Familia
  #
  #     class Example
  #       include Familia
  #       field :name
  #       include Familia::Stamps
  #     end 
  #
  module Stamps
    def self.included(obj)
      obj.module_eval do
        field :created => Integer
        field :updated => Integer
        def init_stamps
          now = Time.now.utc.to_i
          @created ||= now
          @updated ||= now 
        end
        def created
          @created ||= Time.now.utc.to_i
        end
        def updated
          @updated ||= Time.now.utc.to_i
        end
        def created_age
          Time.now.utc.to_i-created
        end
        def updated_age
          Time.now.utc.to_i-updated
        end
        def update_time
          @updated = Time.now.utc.to_i
        end
        def update_time!
          update_time
          save if respond_to? :save
          @updated
        end
      end
    end
  end
  module Status
    def self.included(obj)
      obj.module_eval do
        field :status
        field :message
        def  failure?()        status? 'failure'       end
        def  success?()        status? 'success'       end
        def  pending?()        status? 'pending'       end
        def  expired?()        status? 'expired'       end
        def disabled?()        status? 'disabled'      end
        def  failure!(msg=nil) status! 'failure',  msg end
        def  success!(msg=nil) status! 'success',  msg end
        def  pending!(msg=nil) status! 'pending',  msg end
        def  expired!(msg=nil) status! 'expired',  msg end
        def disabled!(msg=nil) status! 'disabled', msg end
        private
        def status?(s)
          status.to_s == s.to_s
        end
        def status!(s, msg=nil)
          @updated = Time.now.utc.to_f
          @status, @message = s, msg
          save if respond_to? :save
        end
      end
    end
  end
end

module Familia
  module Tools
    extend self
    def move_keys(filter, source_uri, target_uri, &each_key)
      if target_uri == source_uri
        raise "Source and target are the same (#{target_uri})"
      end
      Familia.connect target_uri
      source_keys = Familia.redis(source_uri).keys(filter)
      puts "Moving #{source_keys.size} keys from #{source_uri} to #{target_uri} (filter: #{filter})"
      source_keys.each_with_index do |key,idx|
        type = Familia.redis(source_uri).type key
        ttl = Familia.redis(source_uri).ttl key
        if source_uri.host == target_uri.host && source_uri.port == target_uri.port
          Familia.redis(source_uri).move key, target_uri.db
        else
          case type
          when "string"
            value = Familia.redis(source_uri).get key
          when "list"
            value = Familia.redis(source_uri).lrange key, 0, -1
          when "set"
            value = Familia.redis(source_uri).smembers key
          else
            raise Familia::Problem, "unknown key type: #{type}"
          end
          raise "Not implemented"
        end
        each_key.call(idx, type, key, ttl) unless each_key.nil?
      end
    end
    # Use the return value from each_key as the new key name
    def rename(filter, source_uri, target_uri=nil, &each_key)
      target_uri ||= source_uri
      move_keys filter, source_uri, target_uri if source_uri != target_uri
      source_keys = Familia.redis(source_uri).keys(filter)
      puts "Renaming #{source_keys.size} keys from #{source_uri} (filter: #{filter})"
      source_keys.each_with_index do |key,idx|
        Familia.trace :RENAME1, Familia.redis(source_uri), "#{key}", ''
        type = Familia.redis(source_uri).type key
        ttl = Familia.redis(source_uri).ttl key
        newkey = each_key.call(idx, type, key, ttl) unless each_key.nil?
        Familia.trace :RENAME2, Familia.redis(source_uri), "#{key} -> #{newkey}", caller[0]
        ret = Familia.redis(source_uri).renamenx key, newkey
      end
    end
  end
end


module Familia
  module Collector
    def klasses
      @klasses ||= []
      @klasses
    end
    def included(obj)
      self.klasses << obj
    end
  end  
end

class Symbol
  unless method_defined?(:to_proc)
    def to_proc
      proc { |obj, *args| obj.send(self, *args) }
    end
  end
end

