# lib/familia/connection/connection_chain.rb

require_relative 'default_handler'
require_relative 'fiber_handler'
require_relative 'propvider_handler'

module Familia
  module Connection

    # Manages ordered chain of connection handlers
    class ConnectionChain
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

  end
end
