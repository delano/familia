# frozen_string_literal: true

require_relative 'relations_management'

module Familia
  class Horreum
    # Class-level instance variables
    # These are set up as nil initially and populated later
    @redis = nil
    @identifier = nil
    @fields = nil # []
    @ttl = nil
    @db = nil
    @uri = nil
    @suffix = nil
    @prefix = nil
    @class_redis_types = nil # {}
    @redis_types = nil # {}
    @defined_fields = nil # {}
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
        @redis || Familia.redis(uri)
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
        class_redis_types.has_key? name.to_s.to_sym
      end

      def redis_object?(name)
        redis_types.has_key? name.to_s.to_sym
      end

      def redis_types
        @redis_types ||= {}
        @redis_types
      end

      def defined_fields
        @defined_fields ||= {}
        @defined_fields
      end

      def ttl(v = nil)
        @ttl = v unless v.nil?
        @ttl || (parent ? parent.ttl : nil)
      end

      def db(v = nil)
        @db = v unless v.nil?
        @db || (parent ? parent.db : nil)
      end

      def uri(v = nil)
        @uri = v unless v.nil?
        @uri || (parent ? parent.uri : nil)
      end

      def all(suffix = :object)
        # objects that could not be parsed will be nil
        keys(suffix).collect { |k| from_key(k) }.compact
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

      def from_key(objkey)
        raise ArgumentError, 'Empty key' if objkey.to_s.empty?

        # We use a lower-level method here b/c we're working with the
        # full key and not just the identifier.
        does_exist = redis.exists(objkey).positive?

        Familia.ld "[.from_key] #{self} from key #{objkey} (exists: #{does_exist})"
        Familia.trace :LOAD, redis, objkey, caller if Familia.debug?

        return unless does_exist

        obj = redis.hgetall(objkey) # horreum objects are persisted as redis hashes
        Familia.trace :HGETALL, redis, "#{objkey}: #{obj.inspect}", caller if Familia.debug?

        new(**obj)
      end

      def from_redis(identifier, suffix = :object)
        return nil if identifier.to_s.empty?

        objkey = rediskey(identifier, suffix)
        Familia.ld "[.from_redis] #{self} from key #{objkey})"
        Familia.trace :FROMREDIS, Familia.redis(uri), objkey, caller(1..1).first if Familia.debug?
        from_key objkey
      end

      def exists?(identifier, suffix = :object)
        return false if identifier.to_s.empty?

        objkey = rediskey identifier, suffix

        ret = redis.exists objkey
        if Familia.debug?
          Familia.trace :EXISTS, redis, "#{objkey} #{ret.inspect}",
                        caller
        end
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
  end
end
