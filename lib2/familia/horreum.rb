module Familia

  #
  # Differences between Familia::Horreum and Familia::HashKey:
  #
  #   * Horreum is a module, HashKey is a class. When included in a class,
  #     Horreum appears in the list of ancestors without getting involved
  #     in the class hierarchy.
  #   * HashKey is a wrapper around Redis hash operations where every
  #     value change is performed directly on redis; Horreum is a cache
  #     that performs atomic operations on a hash in redis (via HashKey).
  #
  # Differences between Familia and Familia::Horreum: !==
  #
  #   * Familia provides class/module level access to redis types and
  #     operations; Horreum provides instance-level access to a single
  #     hash in redis.
  #   * Horreum includes Familia and uses `hashkey` to define a redis
  #     has that it refers to as simply "object".
  #   * Horreum applies a default expiry to all keys. 5 years. So the
  #     default behaviour is that all data is stored definitely. It also
  #     uses this expiration as the updated timestamp.
  #
  # Horreum is equivalent to Onetime::RedisHash.
  #
  class Horreum

    class << self
      def inherited(member)
        Familia.ld "[Horreum] Inherited by #{member}"
        member.extend(ClassMethods)
        member.include(InstanceMethods)

        # Tracks all the classes/modules that include Familia. It's
        # 10pm, do you know where you Familia members are?
        Familia.members << member
        #super
      end
    end

    # A default initialize method. This will be replaced
    # if a class defines its own initialize method after
    # including Familia. In that case, the replacement
    # must call initialize_redis_objects.
    def initialize *args, **kwargs
      Familia.ld "[Horreum] Initializing #{self.class} with #{args.inspect} and #{kwargs.inspect}"
      initialize_redis_objects
      init(*args) if respond_to? :init
    end

    def identifier
      send(self.class.identifier)
    end

    def rediskey
      #
    end

    def save
      #
    end

    def update_fields
      #
    end

    def to_h
      #
    end

    def to_a
      #
    end

    def join(*args)
      Familia.join(args.map { |field| send(field) })
    end
  end
end

require_relative 'horreum/class_methods'
require_relative 'horreum/instance_methods'
