# lib/familia/horreum/settings.rb
#
# frozen_string_literal: true

module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Database operations and object management.
  #
  class Horreum
    # Settings - Instance-level configuration methods for Horreum models
    # Provides per-instance settings like logical_database, suffix
    #
    module Settings
      attr_writer :suffix

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

      # Retrieves the prefix for the current instance by delegating to its class.
      #
      # @return [String] The prefix associated with the class of the current instance.
      # @example
      #   instance.prefix
      def prefix
        self.class.prefix
      end

      def suffix
        @suffix || self.class.suffix
      end
    end
  end
end
