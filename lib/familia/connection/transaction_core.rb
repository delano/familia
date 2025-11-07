# lib/familia/connection/transaction_core.rb

module Familia
  module Connection
    # Core transaction logic shared between global and instance transaction methods
    #
    # This module provides unified transaction handling with configurable fallback
    # behavior when transactions are unavailable due to connection handler constraints.
    # Eliminates code duplication between Operations and Horreum Connection modules.
    #
    # ## Transaction Safety Rules
    #
    # ### Rule 1: No Save Operations Inside Transactions
    # The following methods CANNOT be called within a transaction context:
    # - `save`, `save!`, `save_if_not_exists!`, `create!`
    # These methods require reading current state for validation, which would
    # return uninspectable Redis::Future objects inside transactions.
    #
    # ### Rule 2: Reentrant Transaction Behavior
    # Nested transaction calls reuse the same connection and do not create new
    # MULTI/EXEC blocks. This ensures atomicity across nested operations.
    #
    # ### Rule 3: Read Operations Return Futures
    # Inside transactions, read operations return Redis::Future objects that
    # cannot be inspected until the transaction completes. Always check conditions
    # before entering the transaction.
    #
    # ### Rule 4: Connection Handler Compatibility
    # - **FiberTransactionHandler**: Supports reentrant transactions
    # - **ProviderConnectionHandler**: Full transaction support
    # - **CreateConnectionHandler**: Full transaction support
    # - **FiberConnectionHandler**: Blocked (raises OperationModeError)
    # - **DefaultConnectionHandler**: Blocked (raises OperationModeError)
    #
    # @example Correct Pattern: Save Before Transaction
    #   customer = Customer.new(email: 'test@example.com')
    #   customer.save  # Validates unique constraints here
    #
    #   customer.transaction do
    #     customer.increment(:login_count)
    #     customer.hset(:last_login, Time.now.to_i)
    #   end
    #
    # @example Incorrect Pattern: Save Inside Transaction
    #   Customer.transaction do
    #     customer = Customer.new(email: 'test@example.com')
    #     customer.save  # Raises Familia::OperationModeError
    #   end
    #
    # @example Reentrant Transactions
    #   Customer.transaction do |outer_conn|
    #     outer_conn.set('key1', 'value1')
    #
    #     # Nested call reuses same connection - no new MULTI/EXEC
    #     Customer.transaction do |inner_conn|
    #       inner_conn.set('key2', 'value2')  # Same connection as outer
    #     end
    #   end
    #
    # @example Usage in transaction methods
    #   def transaction(&block)
    #     TransactionCore.execute_transaction(-> { dbclient }, &block)
    #   end
    #
    # @see docs/transaction_safety.md for complete safety guidelines
    #
    module TransactionCore
      # Executes a transaction with configurable fallback behavior
      #
      # Handles three transaction scenarios based on connection handler capabilities:
      # 1. Normal transaction (MULTI/EXEC) when handler supports transactions
      # 2. Reentrant transaction when already within a transaction context
      # 3. Individual command execution with configurable error/warn/silent modes
      #
      # ## Safety Mechanisms
      # - Fiber-local storage tracks transaction state across nested calls
      # - Connection handler validation prevents unsafe transaction usage
      # - Automatic cleanup ensures proper state management even on exceptions
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result object with success status and command results
      # @yield [Redis] Redis connection or proxy for command execution
      #
      # @example Basic usage
      #   result = TransactionCore.execute_transaction(-> { dbclient }) do |conn|
      #     conn.set('key1', 'value1')
      #     conn.incr('counter')
      #   end
      #   result.successful?  # => true/false
      #   result.results     # => ["OK", 1]
      #
      def self.execute_transaction(dbclient_proc, &)
        # First, get the connection to populate the handler class
        dbclient_proc.call
        handler_class = Fiber[:familia_connection_handler_class]

        # Check transaction capability
        transaction_capability = handler_class&.allows_transaction

        if transaction_capability == false
          handle_transaction_fallback(dbclient_proc, handler_class, &)
        elsif transaction_capability == :reentrant
          # Already in transaction, just yield the connection
          yield(Fiber[:familia_transaction])
        else
          # Normal transaction flow (includes nil, true, and other values)
          execute_normal_transaction(dbclient_proc, &)
        end
      end

      # Handles transaction fallback based on configured transaction mode
      #
      # Delegates to OperationCore.handle_fallback for consistent behavior
      # across transaction and pipeline operations.
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param handler_class [Class] The connection handler class that blocked transaction
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result from individual command execution or raises error
      #
      def self.handle_transaction_fallback(dbclient_proc, handler_class, &)
        OperationCore.handle_fallback(:transaction, dbclient_proc, handler_class, &)
      end

      # Executes a normal Redis transaction using MULTI/EXEC
      #
      # Handles the standard transaction flow including nested transaction detection,
      # proper Fiber-local state management, and cleanup in ensure blocks.
      #
      # ## Implementation Details
      # - Uses Fiber[:familia_transaction] to track active transaction connection
      # - Reentrant behavior: yields existing connection if already in transaction
      # - All commands queued and executed atomically on EXEC
      # - Returns MultiResult with success status and command results
      #
      # ## Thread Safety
      # Each thread has its own root fiber with isolated fiber-local storage,
      # ensuring transactions don't interfere across threads.
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result object with transaction command results
      #
      def self.execute_normal_transaction(dbclient_proc)
        # Check for existing transaction context
        return yield(Fiber[:familia_transaction]) if Fiber[:familia_transaction]

        command_return_values = dbclient_proc.call.multi do |conn|
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
    end
  end
end
