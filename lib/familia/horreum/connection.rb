# lib/familia/horreum/connection.rb

module Familia
  class Horreum
    # Familia::Horreum::Connection
    #
    module Connection
      attr_reader :uri

      # Returns the Database connection for the class.
      #
      # This method retrieves the Database connection instance for the class. If no
      # connection is set, it initializes a new connection using the provided URI
      # or database configuration.
      #
      # @return [Redis] the Database connection instance.
      #
      def dbclient
        Fiber[:familia_transaction] || @dbclient || Familia.dbclient(uri || logical_database)
      end

      def connect(*)
        Familia.connect(*)
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
        # If we're already in a Familia.pipeline context, just yield the pipeline connection
        if Fiber[:familia_pipeline]
          yield(Fiber[:familia_pipeline])
        else
          # Otherwise, create a local transaction
          block_result = dbclient.pipeline(&)
        end
        block_result
      end
    end
  end
end
