# lib/familia/connection/propvider_handler.rb

module Familia
  module Connection
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
