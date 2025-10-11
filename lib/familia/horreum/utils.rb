# lib/familia/horreum/utils.rb
#
module Familia
  # InstanceMethods - Module containing instance-level methods for Familia
  #
  # This module is included in classes that include Familia, providing
  # instance-level functionality for Database operations and object management.
  #
  class Horreum
    # Utils - Instance-level utility methods for Familia::Horreum
    # Provides identifier handling, dbkey generation, and object inspection
    #
    module Utils
      # +suffix+ is the value to be used at the end of the db key
      # (e.g. `customer:customer_id:scores` would have `scores` as the suffix
      # and `customer_id` would have been the identifier in that case).
      #
      # identifier is the value that distinguishes this object from others.
      # Whether this is a Horreum or DataType object, the value is taken
      # from the `identifier` method).
      #
      def dbkey(suffix = nil, _ignored = nil)
        raise Familia::NoIdentifier, "No identifier for #{self.class}" if identifier.to_s.empty?

        suffix ||= self.suffix # use the instance method to get the default suffix
        self.class.dbkey identifier, suffix
      end

      def join(*args)
        Familia.join(args.map { |field| send(field) })
      end
    end
  end
end
