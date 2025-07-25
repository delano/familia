# lib/familia/connection.rb

require_relative '../../lib/redis_middleware'
require_relative 'multi_result'

# Familia
#
# A family warehouse for your redis data.
#
module Familia
  @uri = URI.parse 'redis://127.0.0.1:6379'
  @redis_clients = {}

  # The Connection module provides Redis connection management for Familia.
  # It allows easy setup and access to Redis clients across different URIs
  # with robust connection pooling for thread safety.
  module Connection
    # @return [URI] The default URI for Redis connections
    attr_reader :uri

    # @return [Hash] A hash of Redis clients, keyed by server ID
    attr_reader :redis_clients

    # @return [Boolean] Whether Redis command logging is enabled
    attr_accessor :enable_redis_logging

    # @return [Boolean] Whether Redis command counter is enabled
    attr_accessor :enable_redis_counter

    # @return [Proc] A callable that provides Redis connections
    attr_accessor :connection_provider

    # @return [Boolean] Whether to require external connections (no fallback)
    attr_accessor :connection_required

    # Sets the default URI for Redis connections.
    #
    # NOTE: uri is not a property of the Settings module b/c it's not
    # configured in class defintions like ttl or logical DB index.
    #
    # @param v [String, URI] The new default URI
    # @example
    #   Familia.uri = 'redis://localhost:6379'
    def uri=(uri)
      @uri = normalize_uri(uri)
    end
    alias url uri
    alias url= uri=

    # Establishes a connection to a Redis server.
    #
    # @param uri [String, URI, nil] The URI of the Redis server to connect to.
    #   If nil, uses the default URI from `@redis_uri_by_class` or `Familia.uri`.
    # @return [Redis] The connected Redis client.
    # @raise [ArgumentError] If no URI is specified.
    # @example
    #   Familia.connect('redis://localhost:6379')
    def connect(uri = nil)
      parsed_uri = normalize_uri(uri)
      serverid = parsed_uri.serverid

      if Familia.enable_redis_logging
        RedisLogger.logger = Familia.logger
        RedisClient.register(RedisLogger)
      end

      if Familia.enable_redis_counter
        # NOTE: This middleware uses AtommicFixnum from concurrent-ruby which is
        # less contentious than Mutex-based counters. Safe for
        RedisClient.register(RedisCommandCounter)
      end

      redis = Redis.new(parsed_uri.conf)

      if @redis_clients.key?(serverid)
        msg = "Overriding existing connection for #{serverid}"
        Familia.warn(msg)
      end

      @redis_clients[serverid] = redis
    end

    def reconnect(uri = nil)
      parsed_uri = normalize_uri(uri)
      serverid = parsed_uri.serverid

      # Close the existing connection if it exists
      @redis_clients[serverid].close if @redis_clients.key?(serverid)

      connect(parsed_uri)
    end

    # Retrieves a Redis connection from the appropriate pool.
    # Handles DB selection automatically based on the URI.
    #
    # @return [Redis] The Redis client for the specified URI
    # @example
    #   Familia.redis('redis://localhost:6379/1')
    #   Familia.redis(2)  # Use DB 2 with default server
    def redis(uri = nil)
      # First priority: Thread-local connection (middleware pattern)
      return Thread.current[:familia_connection] if Thread.current.key?(:familia_connection)

      # Second priority: Connection provider
      return connection_provider.call(uri) if connection_provider

      # Third priority: Fallback behavior or error
      raise Familia::NoConnectionAvailable, 'No connection available.' if connection_required

      # Legacy behavior: create connection
      parsed_uri = normalize_uri(uri)

      # Only cache when no specific URI/DB is requested to avoid DB conflicts
      if uri.nil?
        @redis ||= connect(parsed_uri)
        @redis.select(parsed_uri.db) if parsed_uri.db
        @redis
      else
        # When a specific DB is requested, create a new connection
        # to avoid conflicts with cached connections
        connection = connect(parsed_uri)
        connection.select(parsed_uri.db) if parsed_uri.db
        connection
      end
    end

    # Executes Redis commands atomically within a transaction (MULTI/EXEC).
    #
    # Redis transactions queue commands and execute them atomically as a single unit.
    # All commands succeed together or all fail together, ensuring data consistency.
    #
    # @yield [Redis] The Redis transaction connection
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
    # @note **Comparison of Redis batch operations:**
    #
    #   | Feature         | Multi/Exec      | Pipeline        |
    #   |-----------------|-----------------|-----------------|
    #   | Atomicity       | Yes             | No              |
    #   | Performance     | Good            | Better          |
    #   | Error handling  | All-or-nothing  | Per-command     |
    #   | Use case        | Data consistency| Bulk operations |
    #
    def transaction(&)
      redis.multi do |conn|
        Fiber[:familia_transaction] = conn
        begin
          block_result = yield(conn) # rubocop:disable Lint/UselessAssignment
        ensure
          Fiber[:familia_transaction] = nil # cleanup reference
        end
      end
      block_result
    end
    alias multi transaction

    # Executes Redis commands in a pipeline for improved performance.
    #
    # Pipelines send multiple commands without waiting for individual responses,
    # reducing network round-trips. Commands execute independently and can
    # succeed or fail without affecting other commands in the pipeline.
    #
    # @yield [Redis] The Redis pipeline connection
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
      redis.pipeline do |conn|
        Fiber[:familia_pipeline] = conn
        begin
          block_result = yield(conn) # rubocop:disable Lint/UselessAssignment
        ensure
          Fiber[:familia_pipeline] = nil # cleanup reference
        end
      end
      block_result
    end

    private

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
  end
end
