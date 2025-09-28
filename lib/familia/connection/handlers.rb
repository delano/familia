# lib/familia/connection/handlers.rb

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  module Connection
    # Manages ordered chain of connection handlers
    #
    # NOTE: It is important that the last handler in a responsibility chain
    # either always provides a connection or raises an error. Otherwise the
    # end result will simply be `nil` without any guidance to the caller.
    #
    class ResponsibilityChain
      def initialize
        @handlers = []
      end

      def add_handler(handler)
        @handlers << handler
        self
      end

      def handle(uri)
        @handlers.each do |handler|
          connection = handler.handle(uri)
          if connection
            Fiber[:familia_connection_handler_class] = handler.class
            return connection
          end
        end

        # If we get here, no handler provided a connection
        nil
      end
    end

    # Connection handler base class for Chain of Responsibility pattern.
    # When no arguments are passed, all behaviour is based on the top
    # Familia module itself. e.g. Familia.create_dbclient.
    #
    # Summary of Behaviors
    #
    #   | Handler | Transaction | Pipeline | Ad-hoc Commands |
    #   |---------|------------|----------|-----------------|
    #   | **FiberTransaction** | Reentrant (same conn) | Error | Use transaction conn |
    #   | **FiberConnection** | Error | Error | ✓ Allowed |
    #   | **Provider** | ✓ New checkout | ✓ New checkout | ✓ New checkout |
    #   | **Default** | ✓ With guards | ✓ With guards | ✓ Check mode |
    #   | **Create** | ✓ Fresh conn | ✓ Fresh conn | ✓ Fresh conn |
    #
    # NOTE: Every subclass must provide values for the @allows_transaction
    # and @allows_pipelined attributes.
    #
    class BaseConnectionHandler
      @allows_transaction = true
      @allows_pipelined = true

      class << self
        attr_reader :allows_transaction, :allows_pipelined
      end

      def initialize(familia_module = nil)
        @familia_module = familia_module || Familia
      end

      def handle(uri)
        raise NotImplementedError, 'Subclasses must implement handle'
      end
    end

    # Creates new connections directly, with no caching of any kind. If
    # the make it to here in the chain, it'll create a new connection
    # every time.
    #
    # Fresh connection each time - all operations safe (transactions,
    # pipelined, ad-hoc)
    #
    class CreateConnectionHandler < BaseConnectionHandler
      @allows_transaction = true
      @allows_pipelined = true

      def handle(uri)
        # Create new connection (no module-level caching)
        parsed_uri = @familia_module.normalize_uri(uri)
        client = @familia_module.create_dbclient(parsed_uri)
        Familia.trace :DBCLIENT_DEFAULT, nil, "Created new connection for #{parsed_uri.serverid}"
        client
      end
    end

    # Delegates to user-defined connection provider
    #
    # Provider pattern = full flexibility. Use ad-hoc, operations, whatever you
    # like. For each connection, choose one and then get another connection.
    # Rapid-fire sub ms connection pool connection checkouts are all good
    # and also expected how they are to be used.
    # This is where connection pools live
    #
    class ProviderConnectionHandler < BaseConnectionHandler
      @allows_transaction = true
      @allows_pipelined = true

      def handle(uri)
        return nil unless @familia_module.connection_provider

        @familia_module.trace :DBCLIENT_PROVIDER, nil, 'Using connection provider'

        # Determine the correct URI including logical database if needed
        if uri.nil? && @familia_module.respond_to?(:logical_database) && @familia_module.logical_database
          uri = @familia_module.logical_database
        end

        # Always pass normalized URI with database to provider
        # Provider MUST return connection already on the correct database
        parsed_uri = @familia_module.normalize_uri(uri)
        @familia_module.connection_provider.call(parsed_uri.to_s)
      end
    end

    # Checks for fiber-local connections with version validation
    #
    # Strict Ad-hoc Only. Raise error for transaction, pipeline etc operations.
    #
    #     # Enforce middleware connection constraints
    #     case request.operation
    #     when :transaction
    #       raise Familia::MiddlewareConnectionError,
    #         "Cannot start transaction on middleware-provided connection. " \
    #         "Middleware connections are for ad-hoc commands only."
    #     when :pipeline
    #       raise Familia::MiddlewareConnectionError,
    #         "Cannot start pipeline on middleware-provided connection. " \
    #         "Middleware connections are for ad-hoc commands only."
    #     when :command, nil
    #       # Ad-hoc commands are fine
    #       conn
    #     else
    #       raise "Unknown operation: #{request.operation}"
    #     end
    #
    class FiberConnectionHandler < BaseConnectionHandler
      @allows_transaction = false
      @allows_pipelined = false

      def handle(uri)
        return nil unless Fiber[:familia_connection]

        conn, version = Fiber[:familia_connection]
        if version == @familia_module.middleware_version
          @familia_module.trace :DBCLIENT_FIBER, nil, "Using fiber-local connection for #{uri}"
          conn
        else
          # Version mismatch, clear stale connection
          Fiber[:familia_connection] = nil
          @familia_module.trace :DBCLIENT_FIBER, nil, 'Cleared stale fiber connection (version mismatch)'
          nil
        end
      end
    end

    # Checks for fiber-local transaction connections (highest priority for Horreum)
    #
    # Key insight: Mark that we're in reentrant mode and also track of
    # depth. This allows nested transaction calls to be safely reentrant
    # without breaking Redis's single-level MULTI/EXEC.
    #
    # Reentrant transaction - just yield the existing connection
    # No new MULTI/EXEC, just participate in existing transaction
    # Fiber[:familia_transaction_depth] ||= 0
    # Fiber[:familia_transaction_depth] += 1
    #
    class FiberTransactionHandler < BaseConnectionHandler
      @allows_transaction = :reentrant
      @allows_pipelined = false

      def handle(_uri)
        return nil unless Fiber[:familia_transaction]

        Familia.trace :DBCLIENT_FIBER_TRANSACTION, nil, 'Using fiber-local transaction connection'
        Fiber[:familia_transaction]
      end
    end

    # Checks for a dbclient instance variable
    #
    # This works on any module, class, or instance that implements has a
    # dbclient method. From a Horreum model instance, if you call
    # DefaultConnectionHandler.new(self) it'll return self.dbclient or
    # nil, or you can call DefaultConnectionHandler(self.class) and it'll
    # attempt the same using the model's class.
    #
    # +familia_module+ is required.
    #
    # DefaultConnectionHandler - Single cached connection - block all multi-mode operations
    #
    class DefaultConnectionHandler < BaseConnectionHandler
      @allows_transaction = false
      @allows_pipelined = false

      def initialize(familia_module)
        @familia_module = familia_module
      end

      def handle(_uri)
        dbclient = @familia_module.instance_variable_get(:@dbclient)
        return nil unless dbclient

        Familia.trace :DBCLIENT_INSTVAL_OVERRIDE, nil, "Using @dbclient from #{@familia_module.class}"
        dbclient
      end
    end
  end
end
