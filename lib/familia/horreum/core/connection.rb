# lib/familia/horreum/connection.rb

module Familia
  class Horreum
    # Connection: Valkey connection management for Horreum instances
    # Provides both instance and class-level connection methods
    module Connection
      attr_reader :uri

      # Returns the Database connection for the class using Chain of Responsibility pattern.
      #
      # This method uses a chain of handlers to resolve connections in priority order:
      # 1. FiberTransactionHandler - Fiber[:familia_transaction] (active transaction)
      # 2. DefaultConnectionHandler - Horreum model class-level @dbclient
      # 3. GlobalFallbackHandler - Familia.dbclient(uri || logical_database) (global fallback)
      #
      # @return [Redis] the Database connection instance.
      #
      def dbclient(uri = nil)
        @class_connection_chain ||= build_connection_chain
        @class_connection_chain.handle(uri)
      end

      def connect(*)
        Familia.create_dbclient(*)
      end

      def uri=(uri)
        @uri = normalize_uri(uri)
      end
      alias url uri
      alias url= uri=

      # Perform a sacred Database transaction ritual.
      #
      # This method creates a protective circle around your Database operations,
      # ensuring they all succeed or fail together. It's like a group hug for your
      # data operations, but with more ACID properties.
      #
      # @yield [conn] A block where you can perform your Database incantations.
      # @yieldparam conn [Redis] A Database connection in multi mode.
      #
      # @example Performing a Database rain dance
      #   transaction do |conn|
      #     conn.set("weather", "rainy")
      #     conn.set("mood", "melancholic")
      #   end
      #
      # @note This method works with the global Familia.transaction context when available
      #
      def transaction(&)
        # If we're already in a Familia.transaction context, just yield the multi connection
        if Fiber[:familia_connection]
          yield(Fiber[:familia_connection])
        else
          # Otherwise, create a local transaction
          block_result = dbclient.multi(&)
        end
        block_result
      end
      alias multi transaction

      def pipeline(&)
        # If we're already in a Familia.pipeline context, just yield the pipeline connection
        if Fiber[:familia_pipeline]
          yield(Fiber[:familia_pipeline])
        else
          # Otherwise, create a local transaction
          block_result = dbclient.pipeline(&)
        end
        block_result
      end

      private

      # Builds the class-level connection chain with handlers in priority order
      def build_connection_chain
        Familia::Connection::ResponsibilityChain.new
                                                .add_handler(Familia::Connection::FiberTransactionHandler.new)
                                                .add_handler(Familia::Connection::DefaultConnectionHandler.new(self))
                                                .add_handler(Familia::Connection::CreateConnectionHandler.new)
      end
    end
  end
end
