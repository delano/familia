# lib/familia/data_type/connection.rb

module Familia
  class DataType
    # Connection - Instance-level connection and key generation methods
    #
    # This module provides instance methods for database connection resolution
    # and Redis key generation for DataType objects. It includes shared connection
    # behavior from Familia::Connection::Behavior, enabling transaction and pipeline
    # support for both parent-owned and standalone DataType objects.
    #
    # Key features:
    # * Database connection resolution with Chain of Responsibility pattern
    # * Redis key generation based on parent context
    # * Direct database access for advanced operations
    # * Transaction support (MULTI/EXEC) for atomic operations
    # * Pipeline support for batched command execution
    # * Parent delegation for owned DataType objects
    # * Standalone connection management for independent DataType objects
    #
    # Connection Chain Priority:
    # 1. FiberTransactionHandler - Active transaction context
    # 2. FiberConnectionHandler - Fiber-local connections
    # 3. ProviderConnectionHandler - User-defined connection provider
    # 4. ParentDelegationHandler - Delegate to parent object (primary for owned DataTypes)
    # 5. StandaloneConnectionHandler - Independent DataType connection
    #
    # @example Parent-owned DataType (automatic delegation)
    #   class User < Familia::Horreum
    #     logical_database 2
    #     zset :scores
    #   end
    #
    #   user = User.new(userid: 'user_123')
    #   user.scores.transaction do |conn|
    #     conn.zadd(user.scores.dbkey, 100, 'level1')
    #     conn.zadd(user.scores.dbkey, 200, 'level2')
    #   end
    #
    # @example Standalone DataType with transaction
    #   leaderboard = Familia::SortedSet.new('game:leaderboard')
    #   leaderboard.transaction do |conn|
    #     conn.zadd(leaderboard.dbkey, 500, 'player1')
    #     conn.zadd(leaderboard.dbkey, 600, 'player2')
    #   end
    #
    module Connection
      include Familia::Connection::Behavior

      # Returns the effective URI this DataType will use for connections
      #
      # For parent-owned DataTypes, delegates to parent's URI.
      # For standalone DataTypes with logical_database option, constructs URI with that database.
      # For standalone DataTypes without options, returns global Familia.uri.
      # Explicit @uri assignment (via uri=) takes precedence.
      #
      # @return [URI, nil] The URI for database connections
      #
      def uri
        return @uri if defined?(@uri) && @uri
        return parent.uri if parent && parent.respond_to?(:uri)

        # Check opts[:logical_database] first, then parent's logical_database
        db_num = opts[:logical_database]
        db_num ||= parent.logical_database if parent && parent.respond_to?(:logical_database)

        if db_num
          # Create a new URI with the database number but without custom port
          # This ensures consistent URI representation (e.g., redis://host/db not redis://host:port/db)
          base_uri = Familia.uri
          URI.parse("redis://#{base_uri.host}/#{db_num}")
        else
          Familia.uri
        end
      end

      # Retrieves a Database connection using the Chain of Responsibility pattern
      #
      # Implements connection resolution optimized for DataType usage patterns:
      # - Fast path check for active transaction context
      # - Full connection chain for comprehensive resolution
      # - Parent delegation as primary behavior for owned DataTypes
      # - Standalone connection handling for independent DataTypes
      #
      # Note: We don't cache the connection chain in an instance variable because
      # DataType objects are frozen for thread safety. Building the chain is cheap
      # (just creating handler objects), and the actual connection resolution work
      # is done by the handlers themselves.
      #
      # @param uri [String, URI, Integer, nil] Optional URI for database selection
      # @return [Redis] The Database client for the specified URI
      #
      # @example Getting connection from parent-owned DataType
      #   user.tags.dbclient  # Delegates to user.dbclient
      #
      # @example Getting connection from standalone DataType
      #   cache = Familia::HashKey.new('app:cache', logical_database: 2)
      #   cache.dbclient  # Uses standalone handler with db 2
      #
      def dbclient(uri = nil)
        # Fast path for transaction context (highest priority)
        return Fiber[:familia_transaction] if Fiber[:familia_transaction]

        # Build connection chain (not cached due to frozen objects)
        build_connection_chain.handle(uri)
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
      #
      # Enhanced to work seamlessly with transactions and pipelines. When called
      # within a transaction or pipeline context, uses that connection automatically.
      #
      # @yield [Redis, String] Yields the connection and dbkey to the block
      # @return The return value of the block
      #
      # @example Basic usage
      #   datatype.direct_access do |conn, key|
      #     conn.zadd(key, 100, 'member')
      #   end
      #
      # @example Within transaction (automatic context detection)
      #   datatype.transaction do |trans_conn|
      #     datatype.direct_access do |conn, key|
      #       # conn is the same as trans_conn
      #       conn.zadd(key, 200, 'member')
      #     end
      #   end
      #
      def direct_access
        if Fiber[:familia_transaction]
          # Already in transaction, use that connection
          yield(Fiber[:familia_transaction], dbkey)
        elsif Fiber[:familia_pipeline]
          # Already in pipeline, use that connection
          yield(Fiber[:familia_pipeline], dbkey)
        else
          yield(dbclient, dbkey)
        end
      end

      private

      # Builds the connection chain with handlers in priority order
      #
      # Creates the Chain of Responsibility for connection resolution with
      # DataType-specific handlers. Handlers are checked in order:
      #
      # 1. FiberTransactionHandler - Return active transaction connection
      # 2. FiberConnectionHandler - Use fiber-local connection
      # 3. ProviderConnectionHandler - Delegate to connection provider
      # 4. ParentDelegationHandler - Delegate to parent's connection (primary for owned DataTypes)
      # 5. StandaloneConnectionHandler - Handle standalone DataTypes
      #
      # @return [ResponsibilityChain] Configured connection chain
      #
      def build_connection_chain
        # Create fresh handler instances each time since DataType objects are frozen
        # The chain itself is cached in @connection_chain, so this only runs once
        fiber_connection_handler = Familia::Connection::FiberConnectionHandler.new
        provider_connection_handler = Familia::Connection::ProviderConnectionHandler.new

        # DataType-specific handlers for parent delegation and standalone usage
        parent_delegation_handler = Familia::Connection::ParentDelegationHandler.new(self)
        standalone_connection_handler = Familia::Connection::StandaloneConnectionHandler.new(self)

        Familia::Connection::ResponsibilityChain.new
          .add_handler(Familia::Connection::FiberTransactionHandler.instance)
          .add_handler(fiber_connection_handler)
          .add_handler(provider_connection_handler)
          .add_handler(parent_delegation_handler)
          .add_handler(standalone_connection_handler)
      end
    end
  end
end
