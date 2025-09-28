# lib/familia/connection/default_handler.rb

require_relative 'base_handler'

module Familia
  module Connection
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
  end
end
