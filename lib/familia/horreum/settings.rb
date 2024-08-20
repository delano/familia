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
      attr_writer :dump_method, :load_method, :suffix

      def opts
        @opts ||= {}
        @opts
      end

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

      def db=(v)
        @db = v.to_i
      end

      def db
        @db || self.class.db
      end

      def suffix
        @suffix || self.class.suffix
      end

      def dump_method
        @dump_method || self.class.dump_method
      end

      def load_method
        @load_method || self.class.load_method
      end
    end

    include Settings # these become Horreum instance methods
  end
end
