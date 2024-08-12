# rubocop:disable all

require_relative 'redistype/commands'
require_relative 'redistype/serialization'

module Familia

  # RedisType - Base class for Redis data type wrappers
  #
  # This class provides common functionality for various Redis data types
  # such as String, List, Set, SortedSet, and HashKey.
  #
  # @abstract Subclass and implement Redis data type specific methods
  class RedisType
    @registered_types = {}
    @db = nil
    @ttl = nil

    class << self
      attr_reader :registered_types
      attr_accessor :parent
      attr_writer :ttl, :db, :uri

      # To be called inside every class that inherits RedisType
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

    attr_reader :name, :parent, :opts

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
      Familia.ld " [initializing] #{self.class} #{caller[0]}"
      @name = name
      @name = @name.join(Familia.delim) if @name.is_a?(Array)

      # Remove all keys from the opts that are not in the allowed list
      @opts ||= {}
      @opts = @opts.select { |k, _| %i[class parent ttl default db].include? k }

      init if respond_to? :init
    end

    def redis
      return @redis if @redis

      parent? ? @parent.redis : Familia.redis(opts[:db])
    end

    # Produces the full redis key for this object.
    def rediskey
      if parent?
        @parent.rediskey(name)
      else
        Familia.join([name])
      end


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
