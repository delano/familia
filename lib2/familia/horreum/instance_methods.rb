# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    #
    # TODO: Needs to be gone through like ClassMethods. Then if they're
    # reasonable sizes they can be put into one file again, horreum.rb obvs.
    #
    module InstanceMethods

      # This needs to be called in the initialize method of
      # any class that includes Familia.
      def initialize_redis_objects

        # Generate instances of each RedisType. These need to be
        # unique for each instance of this class so they can piggyback
        # on the specifc index of this instance.
        #
        # i.e.
        #     familia_object.rediskey              == v1:bone:INDEXVALUE:object
        #     familia_object.redis_object.rediskey == v1:bone:INDEXVALUE:name
        #
        # See RedisType.install_redis_object
        self.class.redis_objects.each_pair do |name, redis_object_definition|
          Familia.ld "[#{self.class}] initialize_redis_objects #{name} => #{redis_object_definition}"
          klass = redis_object_definition.klass
          opts = redis_object_definition.opts

          # As a subclass of Familia::Horreum, we add ourselves as the parent
          # automatically. This is what determines the rediskey for RedisType
          # instance and which redis connection.
          #
          #   e.g. If the parent's rediskey is `customer:customer_id:object`
          #     then the rediskey for this RedisType instance will be
          #     `customer:customer_id:name`.
          #
          opts[:parent] = self unless opts.has_key?(:parent)

          # Instantiate the RedisType object and below we store it in
          # an instance variable.
          redis_object = klass.new name, opts

          # Freezes the redis_object, making it immutable.
          # This ensures the object's state remains consistent and prevents any modifications,
          # safeguarding its integrity and making it thread-safe.
          # Any attempts to change the object after this will raise a FrozenError.
          redis_object.freeze

          # e.g. customer.name  #=> `#<Familia::HashKey:0x0000...>`
          instance_variable_set "@#{name}", redis_object
        end
      end

      def qstamp(_quantum = nil, pattern = nil, now = Familia.now)
        self.class.qstamp ttl, pattern, now
      end

      def from_redis
        self.class.from_redis index
      end

      def redis
        self.class.redis
      end

      def redisdetails
        {
          uri: self.class.uri,
          db: self.class.db,
          key: rediskey,
          type: redistype,
          ttl: realttl
        }
      end

      def exists?
        Familia.redis(self.class.uri).exists rediskey
      end

      # +suffix+ is the value to be used at the end of the redis key
      def rediskey(suffix = nil)
        Familia.ld "[rediskey] #{identifier} for #{self.class}"
        raise Familia::NoIdentifier, self.class if identifier.to_s.empty?
        suffix ||= self.suffix
        self.class.rediskey identifier, suffix
      end

      #def rediskey
      #  if parent?
      #    @parent.rediskey(name)
      #  else
      #    name
      #  end
      #
      #  Familia.join([name])
      #end

      def save(meth = :set)
        Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first if Familia.debug?

      end

      def savenx
        save :setnx
      end

      def update!(hsh = nil)
        updated = false

      end

      def destroy!
        ret = self.delete
        ret
      end

      def expire(ttl = nil)
        ttl ||= self.class.ttl
        Familia.redis(self.class.uri).expire rediskey, ttl.to_i
      end

      def realttl
        Familia.redis(self.class.uri).ttl rediskey
      end

      def ttl=(v)
        @ttl = v.to_i
      end

      def ttl
        @ttl || self.class.ttl
      end

      def suffix
        @suffix || self.class.suffix
      end

      def raw(suffix = nil)
        #suffix ||= :object
        redis.get rediskey
      end

      def redisuri(suffix = nil)
        u = Familia.redisuri(self.class.uri) # returns URI::Redis
        u.db ||= self.class.db.to_s # TODO: revisit logic (should the horrerum instance know its uri?)
        u.key = rediskey(suffix)
        u
      end

      def redistype(suffix = nil)

        redis.type rediskey
      end
    end
  end
end
