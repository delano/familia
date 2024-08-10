# frozen_string_literal: true

FAMILIA_LIB_HOME = __dir__ unless defined?(FAMILIA_LIB_HOME)
require 'uri/redis'
require 'gibbler'

# Familia - A Ruby ORM for Redis
#
# Familia provides a way to organize and store Ruby objects in Redis.
# It includes various modules and classes to facilitate object-Redis interactions.
#
# @example Basic usage
#   class Flower < Storable
#     include Familia
#     index [:token, :name]
#     field  :token
#     field  :name
#     list   :owners
#     set    :tags
#     zset   :metrics
#     hash   :props
#     string :value, :default => "GREAT!"
#   end
#
# @see https://github.com/delano/familia
#
module Familia
  include Gibbler::Complex
  @secret = '1-800-AWESOME' # Should be modified via Familia.secret = ''
  @apiversion = nil
  @uri = URI.parse 'redis://127.0.0.1'
  @delim = ':'
  @clients = {}
  @classes = []
  @suffix = :object
  @index = :id
  @debug = false
  @dump_method = :to_json
  @load_method = :from_json

  class << self
    attr_reader :clients, :uri, :logger
    attr_accessor :debug, :secret, :delim, :dump_method, :load_method, :suffix
    attr_writer :apiversion, :index

    alias url uri
    def debug?
      @debug == true
    end

    def info *msg
      warn(*msg)
    end

    def classes(with_redis_objects = false)
      with_redis_objects ? [@classes, RedisObject.classes].flatten : @classes
    end

    def ld *msg
      info(*msg) if debug?
    end

    def trace(label, redis_instance, ident, context = nil)
      return unless Familia.debug?

      codeline = if context
                   context = [context].flatten
                   context.reject! { |line| line =~ %r{lib/familia} }
                   context.first
                 end
      info format('[%s] -> %s <- %s %s', label, codeline, redis_instance.id, ident)
    end

    def uri=(v)
      v = URI.parse v unless URI === v
      @uri = v
    end

    # A convenience method for returning the appropriate Redis
    # connection. If +uri+ is an Integer, we'll treat it as a
    # database number. If it's a String, we'll treat it as a
    # full URI (e.g. redis://1.2.3.4/15).
    # Otherwise we'll return the default connection.
    def redis(uri = nil)
      if uri.is_a?(Integer)
        tmp = Familia.uri
        tmp.db = uri
        uri = tmp
      elsif uri.is_a?(String)
        uri &&= URI.parse uri
      end
      uri ||= Familia.uri
      connect(uri) unless @clients[uri.serverid]
      @clients[uri.serverid]
    end

    def log(level, path)
      logger = Log4r::Logger.new('familia')
      logger.outputters = Log4r::FileOutputter.new 'familia', filename: path
      logger.level = Log4r.const_get(level)
      logger
    end

    def connect(uri = nil)
      uri &&= URI.parse uri if uri.is_a?(String)
      uri ||= Familia.uri
      conf = uri.conf
      redis = Redis.new conf
      Familia.trace(:CONNECT, redis, conf.inspect, caller[0..3])
      @clients[uri.serverid] = redis
    end

    def reconnect_all!
      Familia.classes.each do |klass|
        klass.redis.client.reconnect
        Familia.info "#{klass} ping: #{klass.redis.ping}"
      end
    end

    def connected?(uri = nil)
      uri &&= URI.parse uri if uri.is_a?(String)
      @clients.key?(uri.serverid)
    end

    def index(val = nil)
      @index = val if val
      @index
    end

    def join(*val)
      val.join(Familia.delim)
    end

    def split(val)
      val.split(Familia.delim)
    end

    def rediskey *args
      el = args.flatten.compact
      el.unshift @apiversion unless @apiversion.nil?
      el.join(Familia.delim)
    end

    def apiversion(val = nil, &blk)
      if blk.nil?
        @apiversion = val if val
      else
        tmp = @apiversion
        @apiversion = val
        yield
        @apiversion = tmp
      end
      @apiversion
    end

    def now(name = Time.now)
      name.utc.to_i
    end

    # A quantized timestamp
    # e.g. 12:32 -> 12:30
    #
    def qnow(quantum = 10.minutes, now = Familia.now)
      rounded = now - (now % quantum)
      Time.at(rounded).utc.to_i
    end
  end

  class Problem < RuntimeError; end
  class NoIndex < Problem; end
  class NonUniqueKey < Problem; end

  class NotConnected < Problem
    attr_reader :uri

    def initialize(uri)
      @uri = uri
      super
    end

    def message
      "No client for #{uri.serverid}"
    end
  end

  def self.included(obj)
    obj.send :include, Familia::InstanceMethods
    obj.send :include, Gibbler::Complex
    obj.extend Familia::ClassMethods
    obj.class_zset :instances, class: obj, reference: true
    Familia.classes << obj
  end

  require 'familia/object'
  require 'familia/helpers'
end

module Familia
  # Collector - Module for collecting classes that include it
  #
  # This module is used to keep track of classes that include it,
  # typically used for tracking Familia-enabled classes.
  #
  module Collector
    def klasses
      @klasses ||= []
      @klasses
    end

    def included(obj)
      klasses << obj
    end
  end
end

require_relative 'familia/core_ext'
require_relative 'familia/version'
