# encoding: utf-8
FAMILIA_LIB_HOME = File.expand_path File.dirname(__FILE__) unless defined?(FAMILIA_LIB_HOME)
require 'uri/redis'
require 'gibbler'
require 'familia/core_ext'

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
  @apiversion = nil
  @uri = URI.parse 'redis://127.0.0.1'
  @delim = ':'
  @clients = {}
  @classes = []
  @suffix = :object.freeze
  @index = :id.freeze
  @debug = false.freeze
  @dump_method = :to_json
  @load_method = :from_json
  class << self
    attr_reader :classes, :clients, :uri
    attr_accessor :debug, :secret, :delim, :dump_method, :load_method
    attr_writer :apiversion
    def debug?() @debug == true end
    def info *msg
      STDERR.puts *msg
    end
    def ld *msg
      info *msg if debug?
    end
    def trace label, redis_client, ident, context=nil
      return unless Familia.debug?
      info "%s (%d:%s): %s" % [label, Thread.current.object_id, redis_client.object_id, ident] 
      info "  +-> %s" % [context].flatten[0..3].join("\n      ") if context
    end
    def uri= v
      v = URI.parse v unless URI === v
      @uri = v
    end
    # A convenience method for returning the appropriate Redis
    # connection. If +uri+ is an Integer, we'll treat it as a
    # database number. If it's a String, we'll treat it as a 
    # full URI (e.g. redis://1.2.3.4/15).
    # Otherwise we'll return the default connection. 
    def redis(uri=nil)
      if Integer === uri
        uri = Familia.uri(uri)
      elsif String === uri
        uri &&= URI.parse uri
      end
      uri ||= Familia.uri
      connect(uri) unless @clients[uri.serverid] 
      @clients[uri.serverid]
    end
    def connect(uri=nil)
      uri &&= URI.parse uri if String === uri
      uri ||= Familia.uri
      conf = uri.conf
      conf[:thread_safe] = true
      client = Redis.new conf
      Familia.trace :CONNECT, client, conf.inspect, caller[0..3] if Familia.debug
      @clients[uri.serverid] = client
    end
    def reconnect_all!
      Familia.classes.each do |klass|
        klass.redis.client.reconnect
        Familia.info "#{klass} ping: #{klass.redis.ping}" if debug?
      end
    end
    def connected?(uri=nil)
      uri &&= URI.parse uri if String === uri
      @clients.has_key?(uri.serverid)
    end
    def default_suffix(a=nil) @suffix = a if a; @suffix end
    def default_suffix=(a) @suffix = a end
    def index(r=nil)  @index = r if r; @index end
    def index=(r) @index = r; r end
    def split(r) r.split(Familia.delim) end
    def rediskey *args
      el = args.flatten.compact
      el.unshift @apiversion unless @apiversion.nil?
      el.join(Familia.delim)
    end
    def apiversion(r=nil, &blk)  
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
  end
  
  class Problem < RuntimeError; end
  class NoIndex < Problem; end
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
  
  def self.included(obj)
    obj.send :include, Familia::InstanceMethods
    obj.send :include, Gibbler::Complex
    obj.extend Familia::ClassMethods
    obj.class_set :instances
    # :object is a special redis object because its reserved
    # for storing the marshaled instance data (e.g. to_json).
    # When it isn't defined explicitly we define it here b/c
    # it's assumed to exist in other places (see #save).
    obj.string :object, :class => obj unless obj.redis_object? :object
    Familia.classes << obj
  end
  
  require 'familia/object'
  require 'familia/helpers'

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
