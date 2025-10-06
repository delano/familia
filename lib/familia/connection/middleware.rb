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

      def reconnect!
        # Reconnects with fresh middleware registration
        #
        # This method is useful when middleware needs to be applied to connection pools
        # that were created before middleware was enabled. It:
        #
        # 1. Clears the middleware registration flag to allow re-registration.
        # 2. Re-runs the middleware registration logic.
        # 3. Clears connection chain to force rebuild.
        # 4. Increments middleware version to invalidate cached connections.
        # 5. Clears fiber-local connections.
        #
        # The next connection request will use the updated middleware configuration.
        # Existing connection pools will naturally create new connections with middleware
        # as old connections are cycled out.
        #
        # @example Enable middleware and reconnect
        #   Familia.enable_database_logging = true
        #   Familia.reconnect!
        #
        # @example In test suites
        #   # Test file A creates pools
        #   Familia.connection_provider = ->(uri) { pool.with { |c| c } }
        #
        #   # Test file B enables middleware
        #   Familia.enable_database_logging = true
        #   Familia.reconnect!  # Force new connections with middleware
        #

        # Allow middleware to be re-registered
        @middleware_registered = false
        register_middleware_once

        # Clear connection chain to force rebuild
        @connection_chain = nil

        # Increment version to invalidate all cached connections
        increment_middleware_version!

        # Clear fiber-local connections
        clear_fiber_connection!

        Familia.trace :RECONNECT, nil, 'Connection chain rebuilt with current middleware'
      end

      private

      # Registers middleware once globally, regardless of when clients are created.
      # This prevents duplicate middleware registration and ensures all clients get middleware.
      def register_middleware_once
        # Skip if already registered
        return if @middleware_registered

        # Check if any middleware is enabled
        return unless Familia.enable_database_logging || Familia.enable_database_counter

        if Familia.enable_database_logging
          DatabaseLogger.logger = Familia.logger
          RedisClient.register(DatabaseLogger)
          Familia.trace :MIDDLEWARE_REGISTERED, nil, 'Registered DatabaseLogger'
        end

        if Familia.enable_database_counter
          # NOTE: This middleware uses AtomicFixnum from concurrent-ruby which is
          # less contentious than Mutex-based counters. Safe for production.
          RedisClient.register(DatabaseCommandCounter)
          Familia.trace :MIDDLEWARE_REGISTERED, nil, 'Registered DatabaseCommandCounter'
        end

        # Set flag after successful registration
        @middleware_registered = true
      end
    end
  end
end
