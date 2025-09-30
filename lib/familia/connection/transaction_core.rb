# lib/familia/connection/transaction_core.rb

module Familia
  module Connection
    # Core transaction logic shared between global and instance transaction methods
    #
    # This module provides unified transaction handling with configurable fallback
    # behavior when transactions are unavailable due to connection handler constraints.
    # Eliminates code duplication between Operations and Horreum Connection modules.
    #
    # @example Usage in transaction methods
    #   def transaction(&block)
    #     TransactionCore.execute_transaction(-> { dbclient }, &block)
    #   end
    #
    module TransactionCore
      # Executes a transaction with configurable fallback behavior
      #
      # Handles three transaction scenarios based on connection handler capabilities:
      # 1. Normal transaction (MULTI/EXEC) when handler supports transactions
      # 2. Reentrant transaction when already within a transaction context
      # 3. Individual command execution with configurable error/warn/silent modes
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
      def self.execute_transaction(dbclient_proc, &block)
        # First, get the connection to populate the handler class
        connection = dbclient_proc.call
        handler_class = Fiber[:familia_connection_handler_class]

        # Check transaction capability
        transaction_capability = handler_class&.allows_transaction

        if transaction_capability == false
          handle_transaction_fallback(dbclient_proc, handler_class, &block)
        elsif transaction_capability == :reentrant
          # Already in transaction, just yield the connection
          yield(Fiber[:familia_transaction])
        else
          # Normal transaction flow (includes nil, true, and other values)
          execute_normal_transaction(dbclient_proc, &block)
        end
      end

      private

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
      def self.handle_transaction_fallback(dbclient_proc, handler_class, &block)
        OperationCore.handle_fallback(:transaction, dbclient_proc, handler_class, &block)
      end

      # Executes a normal Redis transaction using MULTI/EXEC
      #
      # Handles the standard transaction flow including nested transaction detection,
      # proper Fiber-local state management, and cleanup in ensure blocks.
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result object with transaction command results
      #
      def self.execute_normal_transaction(dbclient_proc, &block)
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
