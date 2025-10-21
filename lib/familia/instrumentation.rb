# frozen_string_literal: true

require 'concurrent-ruby'

module Familia
  # Provides instrumentation hooks for observability into Familia operations.
  #
  # This module allows applications to register callbacks for various events
  # in Familia's lifecycle, enabling audit trails, performance monitoring,
  # and operational observability.
  #
  # @example Basic usage
  #   Familia.on_command do |cmd, duration, context|
  #     puts "Redis command: #{cmd} (#{duration}μs)"
  #   end
  #
  # @example Audit trail for secrets service
  #   Familia.on_lifecycle do |event, instance, context|
  #     case event
  #     when :save
  #       AuditLog.create!(
  #         event: 'secret_saved',
  #         secret_id: instance.identifier,
  #         user_id: RequestContext.current_user_id
  #       )
  #     end
  #   end
  #
  module Instrumentation
    @hooks = {
      command: Concurrent::Array.new,
      pipeline: Concurrent::Array.new,
      lifecycle: Concurrent::Array.new,
      error: Concurrent::Array.new
    }

    class << self
      # Register a callback for Redis command execution.
      #
      # @yield [cmd, duration, context] Callback block
      # @yieldparam cmd [String] The Redis command name (e.g., "SET", "ZADD")
      # @yieldparam duration [Integer] Command execution duration in microseconds
      # @yieldparam context [Hash] Additional context including:
      #   - :full_command [Array] Complete command with arguments
      #   - :db [Integer] Database number
      #   - :connection_id [String] Connection identifier
      #
      # @example
      #   Familia.on_command do |cmd, duration, ctx|
      #     StatsD.timing("familia.command.#{cmd.downcase}", duration / 1000.0)
      #   end
      #
      def on_command(&block)
        @hooks[:command] << block
      end

      # Register a callback for pipelined Redis operations.
      #
      # @yield [command_count, duration, context] Callback block
      # @yieldparam command_count [Integer] Number of commands in the pipeline
      # @yieldparam duration [Integer] Pipeline execution duration in microseconds
      # @yieldparam context [Hash] Additional context
      #
      # @example
      #   Familia.on_pipeline do |count, duration, ctx|
      #     StatsD.timing("familia.pipeline", duration / 1000.0)
      #     StatsD.gauge("familia.pipeline.commands", count)
      #   end
      #
      def on_pipeline(&block)
        @hooks[:pipeline] << block
      end

      # Register a callback for Horreum lifecycle events.
      #
      # @yield [event, instance, context] Callback block
      # @yieldparam event [Symbol] Lifecycle event (:initialize, :save, :destroy)
      # @yieldparam instance [Familia::Horreum] The object instance
      # @yieldparam context [Hash] Additional context including:
      #   - :duration [Integer] Operation duration in microseconds (for initialize/save)
      #   - :update_expiration [Boolean] Whether TTL was updated (for save)
      #
      # @example
      #   Familia.on_lifecycle do |event, instance, ctx|
      #     case event
      #     when :destroy
      #       Rails.logger.info("Destroyed #{instance.class}:#{instance.identifier}")
      #     end
      #   end
      #
      def on_lifecycle(&block)
        @hooks[:lifecycle] << block
      end

      # Register a callback for error conditions.
      #
      # @yield [error, context] Callback block
      # @yieldparam error [Exception] The error that occurred
      # @yieldparam context [Hash] Additional context including:
      #   - :operation [Symbol] Operation that failed (:serialization, etc.)
      #   - :field [Symbol] Field name (for serialization errors)
      #   - :object_class [String] Class name of the object
      #
      # @example
      #   Familia.on_error do |error, ctx|
      #     Sentry.capture_exception(error, extra: ctx)
      #   end
      #
      def on_error(&block)
        @hooks[:error] << block
      end

      # Notify all registered command hooks.
      # @api private
      def notify_command(cmd, duration, context = {})
        @hooks[:command].each do |hook|
          hook.call(cmd, duration, context)
        rescue => e
          Familia.error("Instrumentation hook failed", error: e.message, hook_type: :command)
        end
      end

      # Notify all registered pipeline hooks.
      # @api private
      def notify_pipeline(command_count, duration, context = {})
        @hooks[:pipeline].each do |hook|
          hook.call(command_count, duration, context)
        rescue => e
          Familia.error("Instrumentation hook failed", error: e.message, hook_type: :pipeline)
        end
      end

      # Notify all registered lifecycle hooks.
      # @api private
      def notify_lifecycle(event, instance, context = {})
        @hooks[:lifecycle].each do |hook|
          hook.call(event, instance, context)
        rescue => e
          Familia.error("Instrumentation hook failed", error: e.message, hook_type: :lifecycle)
        end
      end

      # Notify all registered error hooks.
      # @api private
      def notify_error(error, context = {})
        @hooks[:error].each do |hook|
          hook.call(error, context)
        rescue => e
          # Don't recurse on hook failures - just silently skip
        end
      end
    end
  end
end
