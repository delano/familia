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

      # Returns the Redis connection for the class.
      #
      # This method retrieves the Redis connection instance for the class. If no
      # connection is set, it initializes a new connection using the provided URI
      # or database configuration.
      #
      # @return [Redis] the Redis connection instance.
      #
      def redis
        @redis || Familia.redis(uri || db)
      end

      # Sets or retrieves the unique identifier for the class.
      #
      # This method defines or returns the unique identifier used to generate the
      # Redis key for the object. If a value is provided, it sets the identifier;
      # otherwise, it returns the current identifier.
      #
      # @param [Object] val the value to set as the identifier (optional).
      # @return [Object] the current identifier.
      #
      def identifier(val = nil)
        @identifier = val if val
        @identifier
      end

      # Defines a field for the class and creates accessor methods.
      #
      # This method defines a new field for the class, creating getter and setter
      # instance methods similar to `attr_accessor`. It also generates a fast
      # writer method for immediate persistence to Redis.
      #
      # @param [Symbol, String] name the name of the field to define.
      #
      def field(name)
        fields << name
        attr_accessor name

        # Every field gets a fast writer method for immediately persisting
        fast_writer! name
      end

      # Defines a writer method with a bang (!) suffix for a given attribute name.
      #
      # The dynamically defined method performs the following:
      # - Checks if the correct number of arguments is provided (exactly one).
      # - Converts the provided value to a format suitable for Redis storage.
      # - Uses the existing accessor method to set the attribute value.
      # - Persists the value to Redis immediately using the hset command.
      # - Includes custom error handling to raise an ArgumentError if the wrong number of arguments is given.
      # - Raises a custom error message if an exception occurs during the execution of the method.
      #
      # @param [Symbol, String] name the name of the attribute for which the writer method is defined.
      # @raise [ArgumentError] if the wrong number of arguments is provided.
      # @raise [RuntimeError] if an exception occurs during the execution of the method.
      #
      def fast_writer!(name)
        define_method :"#{name}!" do |*args|
          # Check if the correct number of arguments is provided (exactly one).
          raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1)" if args.size != 1

          value = args.first

          begin
            # Trace the operation if debugging is enabled.
            Familia.trace :FAST_WRITER, redis, "#{name}: #{value.inspect}", caller(1..1) if Familia.debug?

            # Convert the provided value to a format suitable for Redis storage.
            prepared = to_redis(value)
            Familia.ld "[.fast_writer!] #{name} val: #{value.class} prepared: #{prepared.class}"

            # Use the existing accessor method to set the attribute value.
            send :"#{name}=", value

            # Persist the value to Redis immediately using the hset command.
            hset name, prepared
          rescue Familia::Problem => e
            # Raise a custom error message if an exception occurs during the execution of the method.
            raise "#{name}! method failed: #{e.message}", e.backtrace
          end
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

      def all(suffix = nil)
        suffix ||= self.suffix
        # objects that could not be parsed will be nil
        keys(suffix).filter_map { |k| from_rediskey(k) }
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
        fobj = new(*args)
        raise Familia::Problem, "#{self} already exists: #{fobj.rediskey}" if fobj.exists?

        fobj.save
        fobj
      end

      def multiget(*ids)
        ids = rawmultiget(*ids)
        ids.filter_map { |json| from_json(json) }
      end

      def rawmultiget(*ids)
        ids.collect! { |objid| rediskey(objid) }
        return [] if ids.compact.empty?

        Familia.trace :MULTIGET, redis, "#{ids.size}: #{ids}", caller(1..1) if Familia.debug?
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
      #   User.from_rediskey("user:123")  # Returns a User instance if it exists,
      #   nil otherwise
      #
      def from_rediskey(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        # We use a lower-level method here b/c we're working with the
        # full key and not just the identifier.
        does_exist = redis.exists(objkey).positive?

        Familia.ld "[.from_rediskey] #{self} from key #{objkey} (exists: #{does_exist})"
        Familia.trace :FROM_KEY, redis, objkey, caller(1..1) if Familia.debug?

        # This is the reason for calling exists first. We want to definitively
        # and without any ambiguity know if the object exists in Redis. If it
        # doesn't, we return nil. If it does, we proceed to load the object.
        # Otherwise, hgetall will return an empty hash, which will be passed to
        # the constructor, which will then be annoying to debug.
        return unless does_exist

        obj = redis.hgetall(objkey) # horreum objects are persisted as redis hashes
        Familia.trace :FROM_KEY2, redis, "#{objkey}: #{obj.inspect}", caller(1..1) if Familia.debug?

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
      # and suffix, then delegates to `from_rediskey` for the actual retrieval and
      # instantiation.
      #
      # It's a higher-level method that abstracts away the key construction,
      # making it easier to retrieve objects when you only have their
      # identifier.
      #
      # @example
      #   User.from_identifier(123)  # Equivalent to User.from_rediskey("user:123:object")
      #
      def from_identifier(identifier, suffix = nil)
        suffix ||= self.suffix
        return nil if identifier.to_s.empty?

        objkey = rediskey(identifier, suffix)

        Familia.ld "[.from_identifier] #{self} from key #{objkey})"
        Familia.trace :FROM_IDENTIFIER, Familia.redis(uri), objkey, caller(1..1).first if Familia.debug?
        from_rediskey objkey
      end
      alias load from_identifier

      # Checks if an object with the given identifier exists in Redis.
      #
      # @param identifier [String, Integer] The unique identifier for the object.
      # @param suffix [Symbol, nil] The suffix to use in the Redis key (default: class suffix).
      # @return [Boolean] true if the object exists, false otherwise.
      #
      # This method constructs the full Redis key using the provided identifier and suffix,
      # then checks if the key exists in Redis.
      #
      # @example
      #   User.exists?(123)  # Returns true if user:123:object exists in Redis
      #
      def exists?(identifier, suffix = nil)
        suffix ||= self.suffix
        return false if identifier.to_s.empty?

        objkey = rediskey identifier, suffix

        ret = redis.exists objkey
        Familia.trace :EXISTS, redis, "#{objkey} #{ret.inspect}", caller(1..1) if Familia.debug?

        ret.positive? # differs from redis API but I think it's okay bc `exists?` is a predicate method.
      end

      # Destroys an object in Redis with the given identifier.
      #
      # @param identifier [String, Integer] The unique identifier for the object to destroy.
      # @param suffix [Symbol, nil] The suffix to use in the Redis key (default: class suffix).
      # @return [Boolean] true if the object was successfully destroyed, false otherwise.
      #
      # This method constructs the full Redis key using the provided identifier and suffix,
      # then removes the corresponding key from Redis.
      #
      # @example
      #   User.destroy!(123)  # Removes user:123:object from Redis
      #
      def destroy!(identifier, suffix = nil)
        suffix ||= self.suffix
        return false if identifier.to_s.empty?

        objkey = rediskey identifier, suffix

        ret = redis.del objkey
        Familia.trace :DELETED, redis, "#{objkey}: #{ret.inspect}", caller(1..1) if Familia.debug?
        ret.positive?
      end

      # Finds all keys in Redis matching the given suffix pattern.
      #
      # @param suffix [String] The suffix pattern to match (default: '*').
      # @return [Array<String>] An array of matching Redis keys.
      #
      # This method searches for all Redis keys that match the given suffix pattern.
      # It uses the class's rediskey method to construct the search pattern.
      #
      # @example
      #   User.find  # Returns all keys matching user:*:object
      #   User.find('active')  # Returns all keys matching user:*:active
      #
      def find(suffix = '*')
        redis.keys(rediskey('*', suffix)) || []
      end

      # Generates a quantized timestamp based on the given parameters.
      #
      # @param quantum [Integer, nil] The time quantum in seconds (default: class ttl or 10 minutes).
      # @param pattern [String, nil] The strftime pattern to format the timestamp (default: '%H%M').
      # @param now [Time] The current time (default: Familia.now).
      # @return [String] A formatted timestamp string.
      #
      # This method rounds the current time to the nearest quantum and formats it
      # according to the given pattern. It's useful for creating time-based buckets
      # or keys with reduced granularity.
      #
      # @example
      #   User.qstamp(1.hour, '%Y%m%d%H')  # Returns a string like "2023060114" for 2:30 PM
      #
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
      # +suffix+ If a nil value is explicitly passed in, it won't appear in the redis
      # key that's returned. If no suffix is passed in, the class' suffix is used
      # as the default (via the class method self.suffix). It's an important
      # distinction b/c passing in an explicitly nil is how RedisType objects
      # at the class level are created without the global default 'object'
      # suffix. See RedisType#rediskey "parent_class?" for more details.
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
