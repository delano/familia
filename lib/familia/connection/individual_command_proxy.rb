# lib/familia/connection/individual_command_proxy.rb
#
# frozen_string_literal: true

module Familia
  module Connection
    # Proxy class that executes Redis commands individually instead of in a transaction
    #
    # This class intercepts Redis method calls and executes them immediately against
    # the underlying connection, collecting results as if they were part of a transaction.
    # Used as a fallback when transaction mode is unavailable but graceful degradation
    # is preferred over raising an error.
    #
    # @example Usage in transaction fallback
    #   conn = dbclient
    #   proxy = IndividualCommandProxy.new(conn)
    #
    #   proxy.set('key1', 'value1')  # Executes immediately
    #   proxy.incr('counter')        # Executes immediately
    #   proxy.get('key1')           # Executes immediately
    #
    #   results = proxy.collected_results  # => ["OK", 1, "value1"]
    #
    class IndividualCommandProxy
      attr_reader :collected_results

      def initialize(redis_connection)
        @connection = redis_connection
        @collected_results = []
      end

      # Intercepts Redis method calls and executes them immediately
      #
      # @param method_name [Symbol] The Redis method being called
      # @param args [Array] Arguments passed to the Redis method
      # @param kwargs [Hash] Keyword arguments passed to the Redis method
      # @param block [Proc] Block passed to the Redis method
      # @return The result of the Redis command execution
      #
      def method_missing(method_name, *args, **kwargs, &block)
        if @connection.respond_to?(method_name)
          result = @connection.public_send(method_name, *args, **kwargs, &block)
          @collected_results << result
          result
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @connection.respond_to?(method_name, include_private) || super
      end

      # Returns debug information about the proxy state
      #
      # @return [Hash] Debug information including connection class and result count
      def debug_info
        {
          connection_class: @connection.class.name,
          results_count: @collected_results.size,
          results: @collected_results.dup
        }
      end
    end
  end
end
