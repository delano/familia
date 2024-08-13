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
    @valid_options = %i[class parent ttl default db key redis]
    @db = nil
    @ttl = nil
    @dump_method = :to_json
    @load_method = :from_json

    class << self
      attr_reader :registered_types, :valid_options
      attr_accessor :parent, :dump_method, :load_method
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
        @ttl || parent&.ttl
      end

      def db(val = nil)
        @db = val unless val.nil?
        @db || parent&.db
      end

      def uri(val = nil)
        @uri = val unless val.nil?
        @uri || (parent ? parent.uri : Familia.uri)
      end

      def inherited(obj)
        obj.db = db
        obj.ttl = ttl
        obj.uri = uri
        obj.parent = self
        super(obj)
      end

      def valid_keys_only(opts)
        opts.select { |k, _| RedisType.valid_options.include? k }
      end
    end

    attr_reader :name, :parent, :opts
    attr_writer :dump_method, :load_method

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
    # :key => a hardcoded key to use instead of the deriving the from
    # the name and parent (e.g. a derived key: customer:custid:secret_counter).
    #
    # Uses the redis connection of the parent or the value of
    # opts[:redis] or Familia.redis (in that order).
    def initialize(name, opts = {})
      #Familia.ld " [initializing] #{self.class} #{opts}"
      @name = name
      @name = @name.join(Familia.delim) if @name.is_a?(Array)

      # Remove all keys from the opts that are not in the allowed list
      @opts = opts || {}
      @opts = RedisType.valid_keys_only(@opts)

      init if respond_to? :init
    end

    def redis
      return @redis if @redis

      parent? ? parent.redis : Familia.redis(opts[:db])
    end

    # Produces the full redis key for this object.
    def rediskey
      Familia.ld "[rediskey] #{name} for #{self.class} (#{opts})"

      # Return the hardcoded key if it's set. This is useful for
      # support legacy keys that aren't derived in the same way.
      return opts[:key] if opts[:key]

      if parent_instance?
        # This is an instance-level redis object so the parent instance's
        # rediskey method is defined in Familia::Horreum::InstanceMethods.
        parent.rediskey(name)
      elsif parent_class?
        # This is a class-level redis object so the parent class' rediskey
        # method is defined in Familia::Horreum::ClassMethods.
        parent.rediskey(name, nil)
      else
        # This is a standalone RedisType object where it's name
        # is the full key.
        name
      end
    end

    def class?
      !@opts[:class].to_s.empty? && @opts[:class].is_a?(Familia)
    end

    def parent_instance?
      parent.is_a?(Familia::Horreum)
    end

    def parent_class?
      parent.is_a?(Class) && parent <= Familia::Horreum
    end

    def parent?
      parent_class? || parent_instance?
    end

    def parent
      @opts[:parent]
    end

    def ttl
      @opts[:ttl] || self.class.ttl
    end

    def db
      @opts[:db] || self.class.db
    end

    def uri
      @opts[:uri] || self.class.uri
    end

    def dump_method
      @dump_method || self.class.dump_method
    end

    def load_method
      @load_method || self.class.load_method
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
