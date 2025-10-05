# lib/familia/connection/middleware.rb

require_relative '../../middleware/database_logger'

module Familia
  module Connection
    module Middleware
      # @return [Boolean] Whether Database command logging is enabled
      attr_reader :enable_database_logging

      # @return [Boolean] Whether Database command counter is enabled
      attr_reader :enable_database_counter

      # @return [Integer] Current middleware version for cache invalidation
      def middleware_version
        @middleware_version
      end

      # Increments the middleware version, invalidating all cached connections
      def increment_middleware_version!
        @middleware_version += 1
        Familia.trace :MIDDLEWARE_VERSION, nil, "Incremented to #{@middleware_version}"
      end

      # Sets a versioned fiber-local connection
      def set_fiber_connection(connection)
        Fiber[:familia_connection] = [connection, middleware_version]
        Familia.trace :FIBER_CONNECTION, nil, "Set with version #{middleware_version}"
      end

      # Clears the fiber-local connection
      def clear_fiber_connection!
        Fiber[:familia_connection] = nil
        Familia.trace :FIBER_CONNECTION, nil, 'Cleared' if Familia.debug?
      end

      # Sets whether Database command logging is enabled
      # Registers middleware immediately when enabled
      def enable_database_logging=(value)
        @enable_database_logging = value
        register_middleware_once if value
        increment_middleware_version! if value
      end

      # Sets whether Database command counter is enabled
      # Registers middleware immediately when enabled
      def enable_database_counter=(value)
        @enable_database_counter = value
        register_middleware_once if value
        increment_middleware_version! if value
      end

      private

      # Registers middleware once globally, regardless of when clients are created.
      # This prevents duplicate middleware registration and ensures all clients get middleware.
      def register_middleware_once
        return if @middleware_registered

        if Familia.enable_database_logging
          DatabaseLogger.logger = Familia.logger
          RedisClient.register(DatabaseLogger)
        end

        if Familia.enable_database_counter
          # NOTE: This middleware uses AtomicFixnum from concurrent-ruby which is
          # less contentious than Mutex-based counters. Safe for production.
          RedisClient.register(DatabaseCommandCounter)
        end

        @middleware_registered = true
      end
    end
  end
end
