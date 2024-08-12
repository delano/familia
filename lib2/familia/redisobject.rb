# rubocop:disable all


require_relative 'redisobject/commands'
require_relative 'redisobject/serialization'


module Familia

  # RedisObject - Base class for Redis data type wrappers
  #
  # This class provides common functionality for various Redis data types
  # such as String, List, Set, SortedSet, and HashKey.
  #
  # @abstract Subclass and implement Redis data type specific methods
  class RedisObject
    @registered_types = {}
    @db = nil
    @ttl = nil

    class << self
      attr_reader :registered_types
      attr_accessor :parent
      attr_writer :ttl, :db, :uri

      # To be called inside every class that inherits RedisObject
      # +methname+ is the term used for the class and instance methods
      # that are created for the given +type+ (e.g. set, list, etc)
      def register(type, methname)
        Familia.ld "[#{self}] Registering #{type} as #{methname}"

        @registered_types[methname] = type
      end

      def ttl(val = nil)
        @ttl = val unless val.nil?
        @ttl || @parent&.ttl
      end

      def db(val = nil)
        @db = val unless val.nil?
        @db || @parent&.db
      end

      def uri(val = nil)
        @uri = val unless val.nil?
        @uri || (@parent ? @parent.uri : Familia.uri)
      end

      def inherited(obj)
        obj.db = db
        obj.ttl = ttl
        obj.uri = uri
        obj.parent = self
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
    def initialize(name, opts = {})
      @name = name
      @opts = opts
      @name = @name.join(Familia.delim) if @name.is_a?(Array)
      Familia.ld " [initializing] #{self.class} #{caller[0]}"

      @db = @opts.delete(:db)
      @parent = @opts.delete(:parent)
      @ttl ||= @opts.delete(:ttl)
      @redis ||= @opts.delete(:redis)
      @cache = {}
      init if respond_to? :init
    end

    def redis
      return @redis if @redis

      parent? ? @parent.redis : Familia.redis(db)
    end

    # returns a redis key based on the parent
    # object so it will include the proper index.
    def rediskey
      if parent?
        # We need to check if the parent has a specific suffix
        # for the case where we have specified one other than :object.
        suffix = if @parent.is_a?(Familia) && @parent.class.suffix != :object
                   @parent.class.suffix
                 else
                   name
                 end
        k = @parent.rediskey(name, nil)
      else
        k = [name].flatten.compact.join(Familia.delim)
      end

      k
    end

    def class?
      !@opts[:class].to_s.empty? && @opts[:class].is_a?(Familia)
    end

    def parent?
      @parent.is_a?(Class) || @parent.is_a?(Module) || @parent.is_a?(Familia)
    end

    include Commands
    include Serialization
  end

  require_relative 'types/list'
  require_relative 'types/unsorted_set'
  require_relative 'types/sorted_set'
  require_relative 'types/hashkey'
  require_relative 'types/string'
end
