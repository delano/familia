# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Methods that call Redis commands (InstanceMethods)
    #
    # NOTE: There is no hgetall for Horreum. This is because Horreum
    # is a single hash in Redis that we aren't meant to have be working
    # on in memory for more than, making changes -> committing. To
    # emphasize this, instead of "refreshing" the object with hgetall,
    # just load the object again.
    #
    module Commands

      def exists?
        redis.exists rediskey
      end

      def expire(ttl = nil)
        ttl ||= self.class.ttl
        redis.expire rediskey, ttl.to_i
      end

      def realttl
        redis.ttl rediskey
      end

      def hdel!(field)
        redis.hdel rediskey, field
      end

      def redistype(suffix = nil)
        redis.type rediskey(suffix)
      end

      def hmset(suffix = nil)
        redis.hmset rediskey(suffix), to_h
      end

      def delete!
        redis.del rediskey
      end
      protected :delete!

    end

    include Commands # these become Familia::Horreum instance methods
  end
end
