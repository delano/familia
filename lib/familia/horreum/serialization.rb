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

      def save
        Familia.trace :SAVE, Familia.redis(self.class.uri), redisuri, caller.first if Familia.debug?
      end

      def update_fields; end

      def to_h; end

      def to_a; end

    end

    include Serialization # these become Horreum instance methods
  end
end
