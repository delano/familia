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
      # Executes a Redis transaction (MULTI/EXEC) with proper connection handling.
      #
      # Provides atomic execution of multiple Redis commands with automatic connection
      # management and operation mode enforcement. Returns a MultiResult object containing
      # both success status and command results.
      #
      # @param [Proc] block The block containing Redis commands to execute atomically
      # @yield [Redis] conn The Redis connection configured for transaction mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #   (e.g., FiberConnectionHandler or DefaultConnectionHandler that don't support transactions)
      #
      # @example Basic transaction usage
      #   result = Familia.transaction do |conn|
      #     conn.set('key1', 'value1')
      #     conn.set('key2', 'value2')
      #     conn.get('key1')
      #   end
      #   result.successful?    # => true (if all commands succeeded)
      #   result.results        # => ["OK", "OK", "value1"]
      #   result.results.first  # => "OK"
      #
      # @example Checking transaction success
      #   result = Familia.transaction do |conn|
      #     conn.incr('counter')
      #     conn.decr('other_counter')
      #   end
      #
      #   if result.successful?
      #     puts "All commands succeeded: #{result.results}"
      #   else
      #     puts "Some commands failed: #{result.results}"
      #   end
      #
      # @example Nested transactions (reentrant behavior)
      #   result = Familia.transaction do |outer_conn|
      #     outer_conn.set('outer', 'value')
      #
      #     # Nested transaction reuses the same connection
      #     inner_result = Familia.transaction do |inner_conn|
      #       inner_conn.set('inner', 'value')
      #       inner_conn.get('inner')  # Returns the value directly in nested context
      #     end
      #
      #     [outer_result, inner_result]
      #   end
      #
      # @note Connection Handler Compatibility:
      #   - FiberTransactionHandler: Supports reentrant transactions
      #   - ProviderConnectionHandler: Full transaction support
      #   - CreateConnectionHandler: Full transaction support
      #   - FiberConnectionHandler: Blocked (raises OperationModeError)
      #   - DefaultConnectionHandler: Blocked (raises OperationModeError)
      #
      # @note Thread Safety:
      #   Uses Fiber-local storage to maintain transaction context across nested calls
      #   and ensure proper cleanup even when exceptions occur.
      #
      # @see MultiResult For details on the return value structure
      # @see Familia.pipelined For non-atomic command batching
      # @see #batch_update For similar MultiResult pattern in Horreum models
      def transaction(&)
        handler_class = Fiber[:familia_connection_handler_class]

        # Check if transaction allowed
        if handler_class&.allows_transaction == false
          raise Familia::OperationModeError,
                "Cannot start transaction with #{handler_class.name} connection. Use connection pools."
        end

        # Check for nested transaction (handles both reentrant and existing transaction cases)
        return yield(Fiber[:familia_transaction]) if Fiber[:familia_transaction]

        command_return_values = dbclient.multi do |conn|
          Fiber[:familia_transaction] = conn
          begin
            yield(conn)
          ensure
            Fiber[:familia_transaction] = nil
          end
        end

        # Return same MultiResult format as other methods
        summary_boolean = command_return_values.all? { |ret| %w[OK 0 1].include?(ret.to_s) }
        MultiResult.new(summary_boolean, command_return_values)
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
      #   Familia.pipelined do |pipe|
      #     pipe.set("key1", "value1")
      #     pipe.incr("counter")
      #     pipe.lpush("list", "item")
      #   end
      #   # Returns: ["OK", 2, 1] - results of all commands
      #
      # @example Error handling - commands succeed/fail independently
      #   results = Familia.pipelined do |conn|
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
      # Executes Redis commands in a pipeline for improved performance.
      #
      # Batches multiple Redis commands together and sends them in a single network
      # round-trip, improving performance for multiple independent operations. Returns
      # a MultiResult object containing both success status and command results.
      #
      # @param [Proc] block The block containing Redis commands to execute in pipeline
      # @yield [Redis] conn The Redis connection configured for pipelined mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #   (e.g., FiberConnectionHandler or DefaultConnectionHandler that don't support pipelines)
      #
      # @example Basic pipeline usage
      #   result = Familia.pipelined do |conn|
      #     conn.set('key1', 'value1')
      #     conn.set('key2', 'value2')
      #     conn.get('key1')
      #     conn.incr('counter')
      #   end
      #   result.successful?    # => true (if all commands succeeded)
      #   result.results        # => ["OK", "OK", "value1", 1]
      #   result.results.length # => 4
      #
      # @example Performance optimization with pipeline
      #   # Instead of multiple round-trips:
      #   # value1 = redis.get('key1')  # Round-trip 1
      #   # value2 = redis.get('key2')  # Round-trip 2
      #   # value3 = redis.get('key3')  # Round-trip 3
      #
      #   # Use pipeline for single round-trip:
      #   result = Familia.pipelined do |conn|
      #     conn.get('key1')
      #     conn.get('key2')
      #     conn.get('key3')
      #   end
      #   values = result.results  # => ["value1", "value2", "value3"]
      #
      # @example Checking pipeline success
      #   result = Familia.pipelined do |conn|
      #     conn.set('temp_key', 'temp_value')
      #     conn.expire('temp_key', 60)
      #     conn.get('temp_key')
      #   end
      #
      #   if result.successful?
      #     puts "Pipeline completed: #{result.results}"
      #   else
      #     puts "Some operations failed: #{result.results}"
      #   end
      #
      # @example Nested pipelines (reentrant behavior)
      #   result = Familia.pipelined do |outer_conn|
      #     outer_conn.set('outer', 'value')
      #
      #     # Nested pipeline reuses the same connection
      #     inner_result = Familia.pipelined do |inner_conn|
      #       inner_conn.get('outer')  # Returns Redis::Future in nested context
      #     end
      #
      #     outer_conn.get('outer')
      #   end
      #
      # @note Pipeline vs Transaction Differences:
      #   - Pipeline: Commands executed independently, some may succeed while others fail
      #   - Transaction: All-or-nothing execution, commands are atomic as a group
      #   - Pipeline: Better performance for independent operations
      #   - Transaction: Better consistency for related operations
      #
      # @note Connection Handler Compatibility:
      #   - ProviderConnectionHandler: Full pipeline support
      #   - CreateConnectionHandler: Full pipeline support
      #   - FiberTransactionHandler: Blocked (raises OperationModeError)
      #   - FiberConnectionHandler: Blocked (raises OperationModeError)
      #   - DefaultConnectionHandler: Blocked (raises OperationModeError)
      #
      # @note Thread Safety:
      #   Uses Fiber-local storage to maintain pipeline context across nested calls
      #   and ensure proper cleanup even when exceptions occur.
      #
      # @see MultiResult For details on the return value structure
      # @see Familia.transaction For atomic command execution
      # @see #batch_update For similar MultiResult pattern in Horreum models
      def pipelined(&)
        handler_class = Fiber[:familia_connection_handler_class]

        # Check if pipeline allowed
        if handler_class&.allows_pipelined == false
          raise Familia::OperationModeError,
                "Cannot start pipeline with #{handler_class.name} connection. Use connection pools."
        end

        # Check for existing pipeline context
        return yield(Fiber[:familia_pipeline]) if Fiber[:familia_pipeline]

        command_return_values = dbclient.pipelined do |conn|
          Fiber[:familia_pipeline] = conn
          begin
            yield(conn)
          ensure
            Fiber[:familia_pipeline] = nil
          end
        end

        # Return same MultiResult format as other methods
        summary_boolean = command_return_values.all? { |ret| %w[OK 0 1].include?(ret.to_s) }
        MultiResult.new(summary_boolean, command_return_values)
      end
      alias pipeline pipelined

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
