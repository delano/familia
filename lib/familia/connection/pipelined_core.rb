# frozen_string_literal: true

module Familia
  module Connection
    # Pipeline execution with configurable fallback behavior
    #
    # Handles two pipeline scenarios based on connection handler capabilities:
    # 1. Normal pipeline when handler supports pipelines
    # 2. Individual command execution with configurable error/warn/silent modes
    #
    # @see OperationCore For shared fallback logic
    # @see TransactionCore For similar transaction handling
    #
    module PipelineCore
      # Executes a pipeline with configurable fallback behavior
      #
      # Handles pipeline execution based on connection handler capabilities.
      # When handler doesn't support pipelines, fallback behavior is controlled
      # by Familia.pipelined_mode setting.
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result object with success status and command results
      # @yield [Redis] Redis connection or proxy for command execution
      #
      # @example Basic usage
      #   result = PipelineCore.execute_pipeline(-> { dbclient }) do |conn|
      #     conn.set('key1', 'value1')
      #     conn.incr('counter')
      #   end
      #   result.successful?  # => true/false
      #   result.results     # => ["OK", 1]
      #
      # @example With fallback modes
      #   Familia.configure { |c| c.pipelined_mode = :permissive }
      #   result = PipelineCore.execute_pipeline(-> { cached_conn }) do |conn|
      #     conn.set('key', 'value')  # Executes individually, no error
      #   end
      #
      def self.execute_pipeline(dbclient_proc, &block)
        # First, get the connection to populate the handler class
        connection = dbclient_proc.call
        handler_class = Fiber[:familia_connection_handler_class]

        # Check pipeline capability
        pipeline_capability = handler_class&.allows_pipelined

        if pipeline_capability == false
          OperationCore.handle_fallback(:pipeline, dbclient_proc, handler_class, &block)
        else
          # Normal pipeline flow (includes nil, true, and other values)
          execute_normal_pipeline(dbclient_proc, &block)
        end
      end

      private

      # Executes a normal Redis pipeline
      #
      # Handles proper Fiber-local state management and cleanup in ensure blocks.
      # Manages nested pipeline contexts by checking for existing pipeline state.
      #
      # @param dbclient_proc [Proc] Lambda that returns the Redis connection
      # @param block [Proc] Block containing Redis commands to execute
      # @return [MultiResult] Result object with pipeline command results
      #
      def self.execute_normal_pipeline(dbclient_proc, &block)
        # Check for existing pipeline context
        return yield(Fiber[:familia_pipeline]) if Fiber[:familia_pipeline]

        command_return_values = dbclient_proc.call.pipelined do |conn|
          Fiber[:familia_pipeline] = conn
          begin
            yield(conn)
          ensure
            Fiber[:familia_pipeline] = nil
          end
        end

        # Return same MultiResult format as other methods
        # Pipeline success is true if no exceptions occurred (all commands executed)
        summary_boolean = command_return_values.none? { |ret| ret.is_a?(Exception) }
        MultiResult.new(summary_boolean, command_return_values)
      end
    end
  end
end
