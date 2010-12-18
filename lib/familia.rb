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
  @uri = URI.parse 'redis://localhost'
  @delim = ':'
  @clients = {}
  @classes = []
  @conf = {}
  @suffix = :object.freeze
  @index = :id.freeze
  @debug = false.freeze
  @dump_method = :to_json
  @load_method = :from_json
  class << self
    attr_reader :conf, :classes, :clients
    attr_accessor :debug, :secret, :delim, :dump_method, :load_method
    attr_writer :apiversion, :uri
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
    def uri(db=nil)
      if db.nil?
        @uri
      else
        uri = URI.parse @uri.to_s
        uri.db = db
        uri
      end
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
    def conf=(conf={})
      @conf = conf
      @uri = Redis.uri(@conf).freeze
      connect @uri
      @conf
    end
    def redis(uri=nil)
      if Integer === uri
        uri = Familia.uri(uri)
      else
        uri &&= URI.parse uri if String === uri
      end
      uri ||= Familia.uri
      connect(uri) unless @clients[uri.serverid] 
      #STDERR.puts "REDIS: #{uri} #{caller[0]}" if Familia.debug?
      @clients[uri.serverid]
    end
    def connect(uri=nil, local_conf={})
      uri &&= URI.parse uri if String === uri
      uri ||= Familia.uri
      local_conf[:thread_safe] = true
      client = Redis.new local_conf.merge(uri.conf)
      Familia.trace :CONNECT, client, uri.conf.inspect, caller.first
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
    def destroy keyname, uri=nil
      Familia.redis(uri).del keyname
    end
    def exists? keyname, uri=nil
      Familia.redis(uri).exists keyname
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
