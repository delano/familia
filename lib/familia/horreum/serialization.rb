# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Methods that call load and dump (InstanceMethods)
    #
    module Serialization

      attr_writer :redis

      def redis
        @redis || self.class.redis
      end

      def save
        Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first if Familia.debug?

        redis.multi do |conn|

        end
      end

      def update_fields
      end

      def to_h

      end

      def to_a; end

    end

    include Serialization # these become Horreum instance methods
  end
end

__END__



# From RedisHash
def save
  hsh = { :key => identifier }
  ret = update_fields hsh
  ret == "OK"
end

def update_fields hsh={}
  check_identifier!
  hsh[:updated] = OT.now.to_i
  hsh[:created] = OT.now.to_i unless has_key?(:created)
  ret = update hsh  # update is defined in HashKey
  ## NOTE: caching here like this only works if hsh has all keys
  #self.cache.replace hsh
  ret
end
