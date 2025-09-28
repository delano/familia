# lib/familia/horreum/connection.rb

module Familia
  class Horreum
    # Connection: Valkey connection management for Horreum instances
    # Provides both instance and class-level connection methods
    module Connection
      attr_reader :uri

      # Normalizes various URI formats to a consistent URI object
      # Considers the class/instance logical_database when uri is nil or Integer
      def normalize_uri(uri)
        case uri
        when Integer
          new_uri = Familia.uri.dup
          new_uri.db = uri
          new_uri
        when ->(obj) { obj.is_a?(String) || obj.instance_of?(::String) }
          URI.parse(uri)
        when URI
          uri
        when nil
          # Use logical_database if available, otherwise fall back to Familia.uri
          if respond_to?(:logical_database) && logical_database
            new_uri = Familia.uri.dup
            new_uri.db = logical_database
            new_uri
          else
            Familia.uri
          end
        else
          raise ArgumentError, "Invalid URI type: #{uri.class.name}"
        end
      end

      # Creates a new Database connection instance using the class/instance configuration
      def create_dbclient(uri = nil)
        parsed_uri = normalize_uri(uri)
        Familia.create_dbclient(parsed_uri)
      end

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
        create_dbclient(*)
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
        handler_class = Fiber[:familia_connection_class]

        # Check if transaction allowed
        if handler_class&.allows_transaction? == false
          raise Familia::OperationModeError,
            "Cannot start transaction with #{handler_class.name} connection. Use connection pools."
        end

        # Handle reentrant case - already in transaction
        if handler_class&.allows_transaction? == :reentrant
          return yield(Fiber[:familia_transaction])
        end

        # If we're already in a Familia.transaction context, just yield the multi connection
        if Fiber[:familia_transaction]
          yield(Fiber[:familia_transaction])
        else
          # Otherwise, create a local transaction
          block_result = dbclient.multi(&)
        end
        block_result
      end
      alias multi transaction

      def pipeline(&)
        handler_class = Fiber[:familia_connection_class]

        # Check if pipeline allowed
        if handler_class&.allows_pipeline? == false
          raise Familia::OperationModeError,
            "Cannot start pipeline with #{handler_class.name} connection. Use connection pools."
        end

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
          .add_handler(Familia::Connection::ProviderConnectionHandler.new)
          .add_handler(Familia::Connection::DefaultConnectionHandler.new(self))
          .add_handler(Familia::Connection::CreateConnectionHandler.new(self))
      end
    end
  end
end
