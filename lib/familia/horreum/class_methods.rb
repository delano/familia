# frozen_string_literal: true

require_relative 'relations_management'

module Familia
  class Horreum
    # Class-level instance variables
    # These are set up as nil initially and populated later
    @redis = nil
    @identifier = nil
    @ttl = nil
    @db = nil
    @uri = nil
    @suffix = nil
    @prefix = nil
    @fields = nil # []
    @class_redis_types = nil # {}
    @redis_types = nil # {}
    @dump_method = nil
    @load_method = nil

    # ClassMethods: Provides class-level functionality for Horreum
    #
    # This module is extended into classes that include Familia::Horreum,
    # providing methods for Redis operations and object management.
    #
    # Key features:
    # * Includes RelationsManagement for Redis-type field handling
    # * Defines methods for managing fields, identifiers, and Redis keys
    # * Provides utility methods for working with Redis objects
    #
    module ClassMethods
      include Familia::Settings
      include Familia::Horreum::RelationsManagement

      attr_accessor :parent
      attr_writer :redis, :dump_method, :load_method

      def redis
        @redis || Familia.redis(uri || db)
      end

      # The object field or instance method to call to get the unique identifier
      # for that instance. The value returned by this method will be used to
      # generate the key for the object in Redis.
      def identifier(val = nil)
        @identifier = val if val
        @identifier
      end

      # Define a field for the class. This will create getter and setter
      # instance methods just like any "attr_accessor" methods.
      def field(name)
        fields << name
        attr_accessor name

        # Every field gets a fast writer method for immediately persisting
        fast_writer! name
      end

      # @return The return value from redis client for hset command
      def fast_writer!(name)
        define_method :"#{name}!" do |value|
          prepared = to_redis(value)
          Familia.ld "[.fast_writer!] #{name} val: #{value.class} prepared: #{prepared.class}"
          send :"#{name}=", value # use the existing accessor
          hset name, prepared # persist to Redis without delay
        end
      end

      # Returns the list of field names defined for the class in the order
      # that they were defined. i.e. `field :a; field :b; fields => [:a, :b]`.
      def fields
        @fields ||= []
        @fields
      end

      def class_redis_types
        @class_redis_types ||= {}
        @class_redis_types
      end

      def class_redis_types?(name)
        class_redis_types.key? name.to_s.to_sym
      end

      def redis_object?(name)
        redis_types.key? name.to_s.to_sym
      end

      def redis_types
        @redis_types ||= {}
        @redis_types
      end

      def ttl(v = nil)
        @ttl = v unless v.nil?
        @ttl || parent&.ttl
      end

      def db(v = nil)
        @db = v unless v.nil?
        @db || parent&.db
      end

      def uri(v = nil)
        @uri = v unless v.nil?
        @uri || parent&.uri
      end

      def all(suffix = :object)
        # objects that could not be parsed will be nil
        keys(suffix).filter_map { |k| from_key(k) }
      end

      def any?(filter = '*')
        size(filter) > 0
      end

      def size(filter = '*')
        redis.keys(rediskey(filter)).compact.size
      end

      def suffix(a = nil, &blk)
        @suffix = a || blk if a || !blk.nil?
        @suffix || Familia.default_suffix
      end

      def prefix(a = nil)
        @prefix = a if a
        @prefix || name.downcase.gsub('::', Familia.delim).to_sym
      end

      def create *args
        me = from_array(*args)
        raise "#{self} exists: #{me.rediskey}" if me.exists?

        me.save
        me
      end

      def multiget(*ids)
        ids = rawmultiget(*ids)
        ids.filter_map { |json| from_json(json) }
      end

      def rawmultiget(*ids)
        ids.collect! { |objid| rediskey(objid) }
        return [] if ids.compact.empty?

        Familia.trace :MULTIGET, redis, "#{ids.size}: #{ids}", caller if Familia.debug?
        redis.mget(*ids)
      end

      # Retrieves and instantiates an object from Redis using the full object
      # key.
      #
      # @param objkey [String] The full Redis key for the object.
      # @return [Object, nil] An instance of the class if the key exists, nil
      #   otherwise.
      # @raise [ArgumentError] If the provided key is empty.
      #
      # This method performs a two-step process to safely retrieve and
      # instantiate objects:
      #
      # 1. It first checks if the key exists in Redis. This is crucial because:
      #    - It provides a definitive answer about the object's existence.
      #    - It prevents ambiguity that could arise from `hgetall` returning an
      #      empty hash for non-existent keys, which could lead to the creation
      #      of "empty" objects.
      #
      # 2. If the key exists, it retrieves the object's data and instantiates
      #    it.
      #
      # This approach ensures that we only attempt to instantiate objects that
      # actually exist in Redis, improving reliability and simplifying
      # debugging.
      #
      # @example
      #   User.from_key("user:123")  # Returns a User instance if it exists,
      #   nil otherwise
      #
      def from_key(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        # We use a lower-level method here b/c we're working with the
        # full key and not just the identifier.
        does_exist = redis.exists(objkey).positive?

        Familia.ld "[.from_key] #{self} from key #{objkey} (exists: #{does_exist})"
        Familia.trace :FROM_KEY, redis, objkey, caller if Familia.debug?

        # This is the reason for calling exists first. We want to definitively
        # and without any ambiguity know if the object exists in Redis. If it
        # doesn't, we return nil. If it does, we proceed to load the object.
        # Otherwise, hgetall will return an empty hash, which will be passed to
        # the constructor, which will then be annoying to debug.
        return unless does_exist

        obj = redis.hgetall(objkey) # horreum objects are persisted as redis hashes
        Familia.trace :FROM_KEY2, redis, "#{objkey}: #{obj.inspect}", caller if Familia.debug?

        new(**obj)
      end

      # Retrieves and instantiates an object from Redis using its identifier.
      #
      # @param identifier [String, Integer] The unique identifier for the
      #   object.
      # @param suffix [Symbol] The suffix to use in the Redis key (default:
      #   :object).
      # @return [Object, nil] An instance of the class if found, nil otherwise.
      #
      # This method constructs the full Redis key using the provided identifier
      # and suffix, then delegates to `from_key` for the actual retrieval and
      # instantiation.
      #
      # It's a higher-level method that abstracts away the key construction,
      # making it easier to retrieve objects when you only have their
      # identifier.
      #
      # @example
      #   User.from_redis(123)  # Equivalent to User.from_key("user:123:object")
      #
      def from_redis(identifier, suffix = :object)
        return nil if identifier.to_s.empty?

        objkey = rediskey(identifier, suffix)
        Familia.ld "[.from_redis] #{self} from key #{objkey})"
        Familia.trace :FROM_REDIS, Familia.redis(uri), objkey, caller(1..1).first if Familia.debug?
        from_key objkey
      end

      def exists?(identifier, suffix = :object)
        return false if identifier.to_s.empty?

        objkey = rediskey identifier, suffix

        ret = redis.exists objkey
        Familia.trace :EXISTS, redis, "#{objkey} #{ret.inspect}", caller if Familia.debug?
        ret.positive?
      end

      def destroy!(identifier, suffix = :object)
        return false if identifier.to_s.empty?

        objkey = rediskey identifier, suffix

        ret = redis.del objkey
        if Familia.debug?
          Familia.trace :DELETED, redis, "#{objkey}: #{ret.inspect}",
                        caller
        end
        ret.positive?
      end

      def find(suffix = '*')
        redis.keys(rediskey('*', suffix)) || []
      end

      def qstamp(quantum = nil, pattern = nil, now = Familia.now)
        quantum ||= ttl || 10.minutes
        pattern ||= '%H%M'
        rounded = now - (now % quantum)
        Time.at(rounded).utc.strftime(pattern)
      end

      # +identifier+ can be a value or an Array of values used to create the index.
      # We don't enforce a default suffix; that's left up to the instance.
      # The suffix is used to differentiate between different types of objects.
      #
      #
      # A nil +suffix+ will not be included in the key.
      def rediskey(identifier, suffix = self.suffix)
        Familia.ld "[.rediskey] #{identifier} for #{self} (suffix:#{suffix})"
        raise NoIdentifier, self if identifier.to_s.empty?

        identifier &&= identifier.to_s
        Familia.rediskey(prefix, identifier, suffix)
      end

      def dump_method
        @dump_method || :to_json # Familia.dump_method
      end

      def load_method
        @load_method || :from_json # Familia.load_method
      end
    end
    # End of ClassMethods module
  end
end
