# lib/familia/data_type/connection.rb

module Familia
  class DataType
    # Connection - Instance-level connection and key generation methods
    #
    # This module provides instance methods for database connection resolution
    # and Redis key generation for DataType objects.
    #
    # Key features:
    # * Database connection resolution with Chain of Responsibility pattern
    # * Redis key generation based on parent context
    # * Direct database access for advanced operations
    #
    module Connection
      # TODO: Replace with Chain of Responsibility pattern
      def dbclient
        return Fiber[:familia_transaction] if Fiber[:familia_transaction]
        return @dbclient if @dbclient

        # Delegate to parent if present, otherwise fall back to Familia
        parent ? parent.dbclient : Familia.dbclient(opts[:logical_database])
      end

      # Produces the full dbkey for this object.
      #
      # @return [String] The full dbkey.
      #
      # This method determines the appropriate dbkey based on the context of the DataType object:
      #
      # 1. If a hardcoded key is set in the options, it returns that key.
      # 2. For instance-level DataType objects, it uses the parent instance's dbkey method.
      # 3. For class-level DataType objects, it uses the parent class's dbkey method.
      # 4. For standalone DataType objects, it uses the keystring as the full dbkey.
      #
      # For class-level DataType objects (parent_class? == true):
      # - The suffix is optional and used to differentiate between different types of objects.
      # - If no suffix is provided, the class's default suffix is used (via the self.suffix method).
      # - If a nil suffix is explicitly passed, it won't appear in the resulting dbkey.
      # - Passing nil as the suffix is how class-level DataType objects are created without
      #   the global default 'object' suffix.
      #
      # @example Instance-level DataType
      #   user_instance.some_datatype.dbkey  # => "user:123:some_datatype"
      #
      # @example Class-level DataType
      #   User.some_datatype.dbkey  # => "user:some_datatype"
      #
      # @example Standalone DataType
      #   DataType.new("mykey").dbkey  # => "mykey"
      #
      # @example Class-level DataType with explicit nil suffix
      #   User.dbkey("123", nil)  # => "user:123"
      #
      def dbkey
        # Return the hardcoded key if it's set. This is useful for
        # support legacy keys that aren't derived in the same way.
        return opts[:dbkey] if opts[:dbkey]

        if parent_instance?
          # This is an instance-level datatype object so the parent instance's
          # dbkey method is defined in Familia::Horreum::InstanceMethods.
          parent.dbkey(keystring)
        elsif parent_class?
          # This is a class-level datatype object so the parent class' dbkey
          # method is defined in Familia::Horreum::DefinitionMethods.
          parent.dbkey(keystring, nil)
        else
          # This is a standalone DataType object where it's keystring
          # is the full database key (dbkey).
          keystring
        end
      end

      # Provides a structured way to "gear down" to run db commands that are
      # not implemented in our DataType classes since we intentionally don't
      # have a method_missing method.
      def direct_access
        yield(dbclient, dbkey)
      end
    end
  end
end
