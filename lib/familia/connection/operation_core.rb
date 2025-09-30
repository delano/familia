# frozen_string_literal: true

module Familia
  module Connection
    # Shared logic for transaction and pipeline operation fallback handling
    #
    # Provides configurable fallback behavior when connection handlers don't
    # support specific operation modes (transaction/pipeline).
    #
    module OperationCore
      # Handles operation fallback based on configured mode
      #
      # @param operation_type [Symbol] Either :transaction or :pipeline
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param handler_class [Class] The connection handler that blocked operation
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result from individual command execution or raises error
      #
      def self.handle_fallback(operation_type, dbclient_proc, handler_class, &block)
        mode = get_operation_mode(operation_type)

        case mode
        when :strict
          raise Familia::OperationModeError,
                "Cannot start #{operation_type} with #{handler_class.name} connection. Use connection pools."
        when :warn
          log_fallback_warning(operation_type, handler_class)
          execute_individual_commands(dbclient_proc, &block)
        when :permissive
          execute_individual_commands(dbclient_proc, &block)
        else
          # Default to strict mode if invalid setting
          raise Familia::OperationModeError,
                "Cannot start #{operation_type} with #{handler_class.name} connection. Use connection pools."
        end
      end

      # Gets the configured mode for the operation type
      #
      # @param operation_type [Symbol] Either :transaction or :pipeline
      # @return [Symbol] The configured mode (:strict, :warn, :permissive)
      #
      def self.get_operation_mode(operation_type)
        case operation_type
        when :transaction
          Familia.transaction_mode
        when :pipeline
          Familia.pipeline_mode
        else
          :strict
        end
      end

      # Logs fallback warning message
      #
      # @param operation_type [Symbol] Either :transaction or :pipeline
      # @param handler_class [Class] The connection handler class
      #
      def self.log_fallback_warning(operation_type, handler_class)
        message = "#{operation_type.capitalize} unavailable with #{handler_class.name}. Using individual commands."

        if Familia.respond_to?(:logger) && Familia.logger
          Familia.logger.warn message
        else
          warn message
        end
      end

      # Executes commands individually using a proxy that collects results
      #
      # Creates an IndividualCommandProxy that executes each Redis command immediately
      # instead of queuing them in a transaction or pipeline. Results are collected to
      # maintain the same interface as normal operations.
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result object with collected command results
      #
      def self.execute_individual_commands(dbclient_proc, &block)
        conn = dbclient_proc.call
        proxy = IndividualCommandProxy.new(conn)

        # Execute the block with the proxy
        block.call(proxy)

        # Return MultiResult format for consistency
        results = proxy.collected_results
        summary_boolean = results.all? { |ret| !ret.is_a?(Exception) }
        MultiResult.new(summary_boolean, results)
      end
    end
  end
end
