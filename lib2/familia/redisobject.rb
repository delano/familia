# rubocop:disable all

module Familia

  # RedisObject - Base class for Redis data type wrappers
  #
  # This class provides common functionality for various Redis data types
  # such as String, List, Set, SortedSet, and HashKey.
  #
  # @abstract Subclass and implement Redis data type specific methods
  class RedisObject
    @registered_types = {}
    @classes = []
    @db = nil
    @ttl = nil

    class << self
      # To be called inside every class that inherits RedisObject
      # +meth+ becomes the base for the class and instance methods
      # that are created for the given +klass+ (e.g. Obj.list)
      def register(klass, meth)
        Familia.ld "[#{self}] Registering #{klass} as #{meth}"

        @registered_types[meth] = klass
      end

      attr_reader :classes, :registered_types
      attr_accessor :parent
      attr_writer :ttl, :db, :uri

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
        RedisObject.classes << obj
        super(obj)
      end
    end

    attr_reader :name, :parent
    attr_writer :redis

    # RedisObject instances are frozen. `cache` is a hash
    # for you to store values retreived from Redis. This is
    # not used anywhere by default, but you're encouraged
    # to use it in your specific scenarios.
    attr_reader :cache

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
    # :reference => When true the index of the given value will be
    # stored rather than the marshaled value. This assumes that
    # the marshaled object is stored at a separate key. When read,
    # from_redis looks for that separate key and returns the
    # unmarshaled object. :class must be specified. Default: false.
    #
    # :extend => Extend this instance with the functionality in an
    # other module. Literally: "self.extend opts[:extend]".
    #
    # :parent => The Familia object that this redis object belongs
    # to. This can be a class that includes Familia or an instance.
    #
    # :ttl => the time to live in seconds. When not nil, this will
    # set the redis expire for this key whenever #save is called.
    # You can also call it explicitly via #update_expiration.
    #
    # :quantize => append a quantized timestamp to the rediskey.
    # Takes one of the following:
    #   Boolean: include the default stamp (now % 10 minutes)
    #   Integer: the number of seconds to quantize to (e.g. 1.hour)
    #   Array: All arguments for qstamp (quantum, pattern, Time.now)
    #
    # :default => the default value (String-only)
    #
    # :dump_method => the instance method to call to serialize the
    # object before sending it to Redis (default: Familia.dump_method).
    #
    # :load_method => the class method to call to deserialize the
    # object after it's read from Redis (default: Familia.load_method).
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

      extend @opts[:extend] if @opts[:extend].is_a?(Module)

      @db = @opts.delete(:db)
      @parent = @opts.delete(:parent)
      @ttl ||= @opts.delete(:ttl)
      @redis ||= @opts.delete(:redis)
      @cache = {}
      init if respond_to? :init
    end

    def clear_cache
      @cache.clear
    end

    def echo(meth, trace)
      redis.echo "[#{self.class}\##{meth}] #{trace} (#{@opts[:class]}\#)"
    end

    def redis
      return @redis if @redis

      parent? ? @parent.redis : Familia.redis(db)
    end

    # Returns the most likely value for db, checking (in this order):
    #   * the value from :class if it's a Familia object
    #   * the value from :parent
    #   * the value self.class.db
    #   * assumes the db is 0
    #
    # After this is called once, this method will always return the
    # same value.
    def db
      # Note it's important that we select this value at the last
      # possible moment rather than in initialize b/c the value
      # could be modified after that but before this is called.
      if @opts[:class] && @opts[:class].ancestors.member?(Familia)
        @opts[:class].db
      elsif parent?
        @parent.db
      else
        self.class.db || @db || 0
      end
    end

    def ttl
      @ttl ||
        (@parent.ttl if parent?) ||
        (@opts[:class].ttl if class?) ||
        (self.class.ttl if self.class.respond_to?(:ttl))
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
      if @opts[:quantize]
        args = case @opts[:quantize]
               when Numeric
                 [@opts[:quantize]]  # :quantize => 1.minute
               when Array
                 @opts[:quantize]    # :quantize => [1.day, '%m%D']
               else
                 []                  # :quantize => true
               end
        k = [k, qstamp(*args)].join(Familia.delim)
      end
      k
    end

    def qstamp(quantum = nil, pattern = nil, now = Familia.now)
      quantum ||= @opts[:quantize] || ttl || 10.minutes
      case quantum
      when Numeric
        # Handle numeric quantum (e.g., seconds, minutes)
      when Array
        quantum, pattern = *quantum
      end
      now ||= Familia.now
      rounded = now - (now % quantum)

      if pattern.nil?
        Time.at(rounded).utc.to_i # 3605 -> 3600
      else
        Time.at(rounded).utc.strftime(pattern || '%H%M') # 3605 -> '1:00'
      end

    end

    def class?
      !@opts[:class].to_s.empty? && @opts[:class].is_a?(Familia)
    end

    def parent?
     @parent.is_a?(Class) || @parent.is_a?(Module) || @parent.is_a?(Familia)
    end

    def update_expiration(ttl = nil)
      ttl ||= self.ttl
      return if ttl.to_i.zero? # nil will be zero

      Familia.ld "#{rediskey} to #{ttl}"
      expire ttl.to_i
    end

    def move(db)
      redis.move rediskey, db
    end

    def rename(newkey)
      redis.rename rediskey, newkey
    end

    def renamenx(newkey)
      redis.renamenx rediskey, newkey
    end

    def type
      redis.type rediskey
    end

    def delete
      redis.del rediskey
    end
    alias clear delete
    alias del delete

    # def destroy!
    #  clear
    #  # TODO: delete redis objects for this instance
    # end

    def exists?
      redis.exists(rediskey) && !size.zero?
    end

    def realttl
      redis.ttl rediskey
    end

    def expire(sec)
      redis.expire rediskey, sec.to_i
    end

    def expireat(unixtime)
      redis.expireat rediskey, unixtime
    end

    def persist
      redis.persist rediskey
    end

    def dump_method
      @opts[:dump_method] || Familia.dump_method
    end

    def load_method
      @opts[:load_method] || Familia.load_method
    end

    def to_redis(val)
      return val unless @opts[:class]

      ret = case @opts[:class]
            when ::Symbol, ::String, ::Integer, ::Float, Gibbler::Digest
              val
            when ::NilClass
              ''
            else
              if val.is_a?(::String)
                val

              elsif @opts[:reference] == true
                raise Familia::Problem, "#{val.class} does not have an index method" unless val.respond_to? :index
                raise Familia::Problem, "#{val.class} is not Familia (#{name})" unless val.is_a?(Familia)

                val.index

              elsif val.respond_to? dump_method
                val.send dump_method

              else
                raise Familia::Problem, "No such method: #{val.class}.#{dump_method}"
              end
            end

      Familia.ld "[#{self.class}\#to_redis] nil returned for #{@opts[:class]}\##{name}" if ret.nil?
      ret
    end

    def multi_from_redis(*values)
      # Don't use compact! When using compact like this -- as the last
      # expression in the method -- the return value is obviously intentional.
      # Exclamation mark methods have return values too, usually nil. We don't
      # want to return nil here.
      multi_from_redis_with_nil(*values).compact
    end

    # NOTE: `multi` in this method name refers to multiple values from
    # redis and not the Redis server MULTI command.
    def multi_from_redis_with_nil(*values)
      Familia.ld "multi_from_redis: (#{@opts}) #{values}"
      return [] if values.empty?
      return values.flatten unless @opts[:class]

      unless @opts[:class].respond_to?(load_method)
        raise Familia::Problem, "No such method: #{@opts[:class]}##{load_method}"
      end

      if @opts[:reference] == true
        values = @opts[:class].rawmultiget(*values)
      end

      values.collect! do |obj|
        next if obj.nil?

        val = @opts[:class].send load_method, obj
        if val.nil?
          Familia.ld "[#{self.class}\#multi_from_redis] nil returned for #{@opts[:class]}\##{name}"
        end

        val
      rescue StandardError => e
        Familia.info val
        Familia.info "Parse error for #{rediskey} (#{load_method}): #{e.message}"
        Familia.info e.backtrace
        nil
      end

      values
    end

    def from_redis(val)
      return @opts[:default] if val.nil?
      return val unless @opts[:class]

      ret = multi_from_redis val
      ret&.first # return the object or nil
    end
  end

  require_relative 'types/list'
  require_relative 'types/unsorted_set'
  require_relative 'types/sorted_set'
  require_relative 'types/hashkey'
  require_relative 'types/string'
end
