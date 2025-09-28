# lib/familia/connection/base_handler.rb

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  module Connection

    # Manages ordered chain of connection handlers
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
          connection = handler.try_connection(uri)
          return connection if connection
        end

        # If we get here, no handler provided a connection
        # The DefaultConnectionHandler should always return something or raise
        nil
      end
    end

    # Connection handler base class for Chain of Responsibility pattern
    class BaseConnectionHandler
      def initialize(familia_module)
        @familia = familia_module
      end

      def try_connection(uri)
        raise NotImplementedError, 'Subclasses must implement try_connection'
      end
    end

    # Creates new connections directly (no caching at module level)
    class DefaultConnectionHandler < BaseConnectionHandler
      def try_connection(uri)
        # Create new connection (no module-level caching)
        parsed_uri = @familia.normalize_uri(uri)
        client = @familia.create_dbclient(parsed_uri)
        @familia.trace :DBCLIENT_DEFAULT, nil, "Created new connection for #{parsed_uri.serverid}" if @familia.debug?
        client
      end
    end

    # Checks for fiber-local connections with version validation
    class FiberConnectionHandler < BaseConnectionHandler
      def try_connection(uri)
        return nil unless Fiber[:familia_connection]

        conn, version = Fiber[:familia_connection]
        if version == @familia.middleware_version
          @familia.trace :DBCLIENT_FIBER, nil, "Using fiber-local connection for #{uri}" if @familia.debug?
          conn
        else
          # Version mismatch, clear stale connection
          Fiber[:familia_connection] = nil
          @familia.trace :DBCLIENT_FIBER, nil, 'Cleared stale fiber connection (version mismatch)' if @familia.debug?
          nil
        end
      end
    end

    # Delegates to user-defined connection provider
    class ProviderConnectionHandler < BaseConnectionHandler
      def try_connection(uri)
        return nil unless @familia.connection_provider

        # Always pass normalized URI with database to provider
        # Provider MUST return connection already on the correct database
        parsed_uri = @familia.normalize_uri(uri)
        client = @familia.connection_provider.call(parsed_uri.to_s)

        # In debug mode, verify the provider honored the contract
        if @familia.debug? && client&.respond_to?(:connection)
          current_db = client.connection[:db]
          expected_db = parsed_uri.db || 0
          @familia.ld "Connection provider returned client on DB #{current_db}, expected #{expected_db}"
          if current_db != expected_db
            @familia.warn "Connection provider returned client on DB #{current_db}, expected #{expected_db}"
          end
          @familia.trace :DBCLIENT_PROVIDER, nil, 'Using connection provider' if @familia.debug?
        end

        client
      end
    end
  end
end
