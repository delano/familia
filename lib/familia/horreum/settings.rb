# lib/familia/horreum/settings.rb
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Database operations and object management.
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

      def logical_database=(v)
        @logical_database = v.to_i
      end

      def logical_database
        @logical_database || self.class.logical_database
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
