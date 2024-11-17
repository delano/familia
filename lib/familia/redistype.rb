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
    include Familia::Base
    extend Familia::Features

    @registered_types = {}
    @valid_options = %i[class parent ttl default db key redis suffix prefix]
    @db = nil

    feature :expiration
    feature :quantization

    class << self
      attr_reader :registered_types, :valid_options
      attr_accessor :parent
      attr_writer :db, :uri
    end

    module ClassMethods
      # To be called inside every class that inherits RedisType
      # +methname+ is the term used for the class and instance methods
      # that are created for the given +klass+ (e.g. set, list, etc)
      def register(klass, methname)
        Familia.ld "[#{self}] Registering #{klass} as #{methname.inspect}"

        @registered_types[methname] = klass
      end


      def uri(val = nil)
        @uri = val unless val.nil?
        @uri || (parent ? parent.uri : Familia.uri)
      end

      def inherited(obj)
        Familia.trace :REDISTYPE, nil, "#{obj} is my kinda type", caller(1..1) if Familia.debug?
        obj.db = db
        obj.ttl = ttl # method added via Features::Expiration
        obj.uri = uri
        obj.parent = self
        super(obj)
      end

      def valid_keys_only(opts)
        opts.select { |k, _| RedisType.valid_options.include? k }
      end
    end
    extend ClassMethods

    attr_reader :keystring, :parent, :opts
    attr_writer :dump_method, :load_method

    # +keystring+: If parent is set, this will be used as the suffix
    # for rediskey. Otherwise this becomes the value of the key.
    # If this is an Array, the elements will be joined.
    #
    # Options:
    #
    # :class => A class that responds to Familia.load_method and
    # Familia.dump_method. These will be used when loading and
    # saving data from/to redis to unmarshal/marshal the class.
    #
    # :parent => The Familia object that this redistype object belongs
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
    # :suffix => the suffix to use for the key (e.g. 'scores' in customer:custid:scores).
    # :prefix => the prefix to use for the key (e.g. 'customer' in customer:custid:scores).
    #
    # Connection precendence: uses the redis connection of the parent or the
    # value of opts[:redis] or Familia.redis (in that order).
    def initialize(keystring, opts = {})
      #Familia.ld " [initializing] #{self.class} #{opts}"
      @keystring = keystring
      @keystring = @keystring.join(Familia.delim) if @keystring.is_a?(Array)

      # Remove all keys from the opts that are not in the allowed list
      @opts = opts || {}
      @opts = RedisType.valid_keys_only(@opts)

      # Apply the options to instance method setters of the same name
      @opts.each do |k, v|
        # Bewarde logging :parent instance here implicitly calls #to_s which for
        # some classes could include the identifier which could still be nil at
        # this point. This would result in a Familia::Problem being raised. So
        # to be on the safe-side here until we have a better understanding of
        # the issue, we'll just log the class name for each key-value pair.
        Familia.ld " [setting] #{k} #{v.class}"
        send(:"#{k}=", v) if respond_to? :"#{k}="
      end

      init if respond_to? :init
    end

    def redis
      return @redis if @redis

      parent? ? parent.redis : Familia.redis(opts[:db])
    end

    # Produces the full Redis key for this object.
    #
    # @return [String] The full Redis key.
    #
    # This method determines the appropriate Redis key based on the context of the RedisType object:
    #
    # 1. If a hardcoded key is set in the options, it returns that key.
    # 2. For instance-level RedisType objects, it uses the parent instance's rediskey method.
    # 3. For class-level RedisType objects, it uses the parent class's rediskey method.
    # 4. For standalone RedisType objects, it uses the keystring as the full Redis key.
    #
    # For class-level RedisType objects (parent_class? == true):
    # - The suffix is optional and used to differentiate between different types of objects.
    # - If no suffix is provided, the class's default suffix is used (via the self.suffix method).
    # - If a nil suffix is explicitly passed, it won't appear in the resulting Redis key.
    # - Passing nil as the suffix is how class-level RedisType objects are created without
    #   the global default 'object' suffix.
    #
    # @example Instance-level RedisType
    #   user_instance.some_redistype.rediskey  # => "user:123:some_redistype"
    #
    # @example Class-level RedisType
    #   User.some_redistype.rediskey  # => "user:some_redistype"
    #
    # @example Standalone RedisType
    #   RedisType.new("mykey").rediskey  # => "mykey"
    #
    # @example Class-level RedisType with explicit nil suffix
    #   User.rediskey("123", nil)  # => "user:123"
    #
    def rediskey
      # Return the hardcoded key if it's set. This is useful for
      # support legacy keys that aren't derived in the same way.
      return opts[:key] if opts[:key]

      if parent_instance?
        # This is an instance-level redistype object so the parent instance's
        # rediskey method is defined in Familia::Horreum::InstanceMethods.
        parent.rediskey(keystring)
      elsif parent_class?
        # This is a class-level redistype object so the parent class' rediskey
        # method is defined in Familia::Horreum::ClassMethods.
        parent.rediskey(keystring, nil)
      else
        # This is a standalone RedisType object where it's keystring
        # is the full redis key.
        keystring
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

  require_relative 'redistype/types/list'
  require_relative 'redistype/types/unsorted_set'
  require_relative 'redistype/types/sorted_set'
  require_relative 'redistype/types/hashkey'
  require_relative 'redistype/types/string'
end
