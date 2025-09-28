# lib/familia/connection/operations.rb

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  module Connection
    module Operations
      # Executes Database commands atomically within a transaction (MULTI/EXEC).
      #
      # Database transactions queue commands and execute them atomically as a single unit.
      # All commands succeed together or all fail together, ensuring data consistency.
      #
      # @yield [Redis] The Database transaction connection
      # @return [Array] Results of all commands executed in the transaction
      #
      # @example Basic transaction usage
      #   Familia.transaction do |trans|
      #     trans.set("key1", "value1")
      #     trans.incr("counter")
      #     trans.lpush("list", "item")
      #   end
      #   # Returns: ["OK", 2, 1] - results of all commands
      #
      # @note **Comparison of Database batch operations:**
      #
      #   | Feature         | Multi/Exec      | Pipeline        |
      #   |-----------------|-----------------|-----------------|
      #   | Atomicity       | Yes             | No              |
      #   | Performance     | Good            | Better          |
      #   | Error handling  | All-or-nothing  | Per-command     |
      #   | Use case        | Data consistency| Bulk operations |
      #
      def transaction(&)
        # Check for nested transaction
        return yield(Fiber[:familia_transaction]) if Fiber[:familia_transaction]

        block_result = nil
        previous_conn = Fiber[:familia_connection]

        dbclient.multi do |conn|
          Fiber[:familia_transaction] = conn
          begin
            block_result = yield(conn)
          ensure
            Fiber[:familia_transaction] = nil
            Fiber[:familia_connection] = previous_conn # restore previous context
          end
        end
        # Return the multi result which contains the transaction results
      end
      alias multi transaction

      # Executes Database commands in a pipeline for improved performance.
      #
      # Pipelines send multiple commands without waiting for individual responses,
      # reducing network round-trips. Commands execute independently and can
      # succeed or fail without affecting other commands in the pipeline.
      #
      # @yield [Redis] The Database pipeline connection
      # @return [Array] Results of all commands executed in the pipeline
      #
      # @example Basic pipeline usage
      #   Familia.pipeline do |pipe|
      #     pipe.set("key1", "value1")
      #     pipe.incr("counter")
      #     pipe.lpush("list", "item")
      #   end
      #   # Returns: ["OK", 2, 1] - results of all commands
      #
      # @example Error handling - commands succeed/fail independently
      #   results = Familia.pipeline do |conn|
      #     conn.set("valid_key", "value")     # This will succeed
      #     conn.incr("string_key")            # This will fail (wrong type)
      #     conn.set("another_key", "value2")  # This will still succeed
      #   end
      #   # Returns: ["OK", Redis::CommandError, "OK"]
      #   # Notice how the error doesn't prevent other commands from executing
      #
      # @example Contrast with transaction behavior
      #   results = Familia.transaction do |conn|
      #     conn.set("inventory:item1", 100)
      #     conn.incr("invalid_key")        # Fails, rolls back everything
      #     conn.set("inventory:item2", 200) # Won't be applied
      #   end
      #   # Result: neither item1 nor item2 are set due to the error
      #
      def pipeline(&)
        # Check for existing pipeline context
        return yield(Fiber[:familia_pipeline]) if Fiber[:familia_pipeline]

        block_result = nil
        previous_conn = Fiber[:familia_connection]

        dbclient.pipelined do |conn|
          Fiber[:familia_pipeline] = conn
          begin
            block_result = yield(conn)
          ensure
            Fiber[:familia_pipeline] = nil
            Fiber[:familia_connection] = previous_conn # leave nothing but footprints
          end
        end
        # Return the pipeline result which contains the command results
      end

      # Provides explicit access to a Database connection.
      #
      # This method is useful when you need direct access to a connection
      # for operations not covered by other methods. The connection is
      # properly managed and returned to the pool (if using connection_provider).
      #
      # @yield [Redis] A Database connection
      # @return The result of the block
      #
      # @example Using with_dbclient for custom operations
      #   Familia.with_dbclient do |conn|
      #     conn.set("custom_key", "value")
      #     conn.expire("custom_key", 3600)
      #   end
      #
      def with_dbclient(&)
        yield dbclient
      end

      # Provides explicit access to an isolated Database connection for temporary operations.
      #
      # This method creates a new connection that won't interfere with the cached
      # connection pool, executes the given block with that connection, and ensures
      # the connection is properly closed afterward.
      #
      # Perfect for database scanning, inspection, or migration operations where
      # you need to access different databases without affecting your models'
      # normal connections.
      #
      # @param uri [String, URI, Integer, nil] The URI or database number to connect to.
      # @yield [Redis] An isolated Database connection
      # @return The result of the block
      #
      # @example Safely scanning for legacy data
      #   Familia.with_isolated_dbclient(5) do |conn|
      #     conn.keys("session:*")
      #   end
      #
      # @example Performing migration tasks
      #   Familia.with_isolated_dbclient(1) do |conn|
      #     conn.scan_each(match: "user:*") { |key| puts key }
      #   end
      #
      def with_isolated_dbclient(uri = nil, &)
        client = isolated_dbclient(uri)
        begin
          yield client
        ensure
          client&.close
        end
      end
    end
  end
end
