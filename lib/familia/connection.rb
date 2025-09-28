# lib/familia/connection.rb

require_relative '../../lib/middleware/database_middleware'
require_relative 'connection/connection_chain'
require_relative 'multi_result'

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  @uri = URI.parse 'redis://127.0.0.1:6379'
  @middleware_registered = false
  @middleware_version = 0

  # The Connection module provides Database connection management for Familia.
  # It allows easy setup and access to Database clients across different URIs
  # with robust connection pooling for thread safety.
  module Connection
    # @return [URI] The default URI for Database connections
    attr_reader :uri

    # @return [Integer] Current middleware version for cache invalidation
    def middleware_version
      @middleware_version
    end

    # Increments the middleware version, invalidating all cached connections
    def increment_middleware_version!
      @middleware_version += 1
      Familia.trace :MIDDLEWARE_VERSION, nil, "Incremented to #{@middleware_version}" if Familia.debug?
    end

    # Sets a versioned fiber-local connection
    def set_fiber_connection(connection)
      Fiber[:familia_connection] = [connection, middleware_version]
      Familia.trace :FIBER_CONNECTION, nil, "Set with version #{middleware_version}" if Familia.debug?
    end

    # Clears the fiber-local connection
    def clear_fiber_connection!
      Fiber[:familia_connection] = nil
      Familia.trace :FIBER_CONNECTION, nil, "Cleared" if Familia.debug?
    end

    # @return [Boolean] Whether Database command logging is enabled
    attr_reader :enable_database_logging

    # @return [Boolean] Whether Database command counter is enabled
    attr_reader :enable_database_counter

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

    # @return [Proc] A callable that provides Database connections
    # The provider should accept a URI string and return a Redis connection
    # already connected to the correct database specified in the URI.
    #
    # @example Setting a connection provider
    #   Familia.connection_provider = ->(uri) do
    #     pool = ConnectionPool.new { Redis.new(url: uri) }
    #     pool.with { |conn| conn }
    #   end
    attr_reader :connection_provider

    # Sets the connection provider and bumps middleware version
    def connection_provider=(provider)
      @connection_provider = provider
      increment_middleware_version! if provider
      @connection_chain = nil # Force rebuild of chain
    end

    # @return [Boolean] Whether to require external connections (no fallback)
    attr_accessor :connection_required

    # Sets the default URI for Database connections.
    #
    # NOTE: uri is not a property of the Settings module b/c it's not
    # configured in class defintions like default_expiration or logical DB index.
    #
    # @param uri [String, URI] The new default URI
    # @example Familia.uri = 'redis://localhost:6379'
    def uri=(uri)
      @uri = normalize_uri(uri)
    end
    alias url uri
    alias url= uri=

    # Creates a new Database connection instance.
    #
    # This method always creates a fresh connection and does not use caching.
    # Each call returns a new Redis client instance that you are responsible
    # for managing and closing when done.
    #
    # @param uri [String, URI, nil] The URI of the Database server to connect to.
    #   If nil, uses the default URI from Familia.uri.
    # @return [Redis] A new Database client connection.
    # @raise [ArgumentError] If no URI is specified.
    #
    # @example Creating a new connection
    #   client = Familia.create_dbclient('redis://localhost:6379')
    #   client.ping
    #   client.close
    #
    def create_dbclient(uri = nil)
      parsed_uri = normalize_uri(uri)

      # Register middleware only once, globally
      register_middleware_once

      Redis.new(parsed_uri.conf)
    end
    alias connect create_dbclient # backwards compatibility
    alias isolated_dbclient create_dbclient # matches with_isolated_dbclient api

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



    # Retrieves a Database connection using the Chain of Responsibility pattern.
    # Handles DB selection automatically based on the URI.
    #
    # @return [Redis] The Database client for the specified URI
    # @example Familia.dbclient('redis://localhost:6379/1')
    #   Familia.dbclient(2)  # Use DB 2 with default server
    def dbclient(uri = nil)
      @connection_chain ||= build_connection_chain
      @connection_chain.handle(uri)
    end

    # Builds the connection chain with handlers in priority order
    def build_connection_chain
      ConnectionChain.new
        .add_handler(FiberConnectionHandler.new(self))
        .add_handler(ProviderConnectionHandler.new(self))
        .add_handler(DefaultConnectionHandler.new(self))
    end

    # Make normalize_uri public for handlers to use
    # Normalizes various URI formats to a consistent URI object
    def normalize_uri(uri)
      case uri
      when Integer
        new_uri = Familia.uri.dup
        new_uri.db = uri
        new_uri
      when ->(obj) { obj.is_a?(String) || obj.instance_of?(::String) }
        URI.parse(uri)
      when URI
        uri
      when nil
        Familia.uri
      else
        raise ArgumentError, "Invalid URI type: #{uri.class.name}"
      end
    end

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
      block_result = nil
      dbclient.multi do |conn|
        Fiber[:familia_transaction] = conn
        begin
          block_result = yield(conn)
        ensure
          Fiber[:familia_transaction] = nil # cleanup reference
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
      block_result = nil
      dbclient.pipelined do |conn|
        Fiber[:familia_pipeline] = conn
        begin
          block_result = yield(conn)
        ensure
          Fiber[:familia_pipeline] = nil # cleanup reference
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
