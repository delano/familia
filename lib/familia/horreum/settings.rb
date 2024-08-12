# rubocop:disable all
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Settings - Module containing settings for Familia::Horreum (InstanceMethods)
    #
    module Settings

      def redisdetails
        {
          uri: self.class.uri,
          db: self.class.db,
          key: rediskey,
          type: redistype,
          ttl: ttl,
          realttl: realttl
        }
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

    end

    include Settings # these become Horreum instance methods
  end
end
