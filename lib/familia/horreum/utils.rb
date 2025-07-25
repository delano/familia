# lib/familia/horreum/utils.rb
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Redis operations and object management.
  #
  class Horreum

    # Utils - Module containing utility methods for Familia::Horreum (InstanceMethods)
    #
    module Utils

      def redisuri(suffix = nil)
        u = Familia.redisuri(self.class.uri) # returns URI::Redis
        u.logical_database = logical_database if logical_database # override the logical_database if we have one
        u.key = dbkey(suffix)
        u
      end

      # +suffix+ is the value to be used at the end of the redis key
      # (e.g. `customer:customer_id:scores` would have `scores` as the suffix
      # and `customer_id` would have been the identifier in that case).
      #
      # identifier is the value that distinguishes this object from others.
      # Whether this is a Horreum or DataType object, the value is taken
      # from the `identifier` method).
      #
      def dbkey(suffix = nil, ignored = nil)
        raise Familia::NoIdentifier, "No identifier for #{self.class}" if identifier.to_s.empty?
        suffix ||= self.suffix # use the instance method to get the default suffix
        self.class.dbkey identifier, suffix
      end

      def join(*args)
        Familia.join(args.map { |field| send(field) })
      end
    end

    include Utils # these become Horreum instance methods
  end
end
