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
    module Commands

      def exists?
        Familia.redis(self.class.uri).exists rediskey
      end

      def expire(ttl = nil)
        ttl ||= self.class.ttl
        Familia.redis(self.class.uri).expire rediskey, ttl.to_i
      end

      def realttl
        Familia.redis(self.class.uri).ttl rediskey
      end

      def destroy!
        ret = self.delete
        ret
      end

      def raw(suffix = nil)
        #suffix ||= :object
        redis.get rediskey
      end

      def redistype(suffix = nil)
        redis.type rediskey
      end

    end

    include Commands # these become Horreum instance methods
  end
end
