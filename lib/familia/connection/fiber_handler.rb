# lib/familia/connection/fiber_handler.rb

module Familia
  module Connection
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
  end
end
