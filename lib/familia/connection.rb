# frozen_string_literal: true

require 'connection_pool'
require_relative '../../lib/redis_middleware'

#
module Familia
  @uri = URI.parse 'redis://127.0.0.1'
  @connection_pools = {}
  @redis_uri_by_class = {}

  # Connection pool configuration
  @pool_size = 10
  @pool_timeout = 5
  @enable_connection_pool = true

  # The Connection module provides Redis connection management for Familia.
  # It allows easy setup and access to Redis clients across different URIs
  # with robust connection pooling for thread safety.
  module Connection
    # @return [Hash] A hash of connection pools, keyed by server ID
    attr_reader :connection_pools

    # @return [URI] The default URI for Redis connections
    attr_reader :uri

    # @return [Boolean] Whether Redis command logging is enabled
    attr_accessor :enable_redis_logging

    # @return [Boolean] Whether Redis command counter is enabled
    attr_accessor :enable_redis_counter

    # @return [Boolean] Whether connection pooling is enabled
    attr_accessor :enable_connection_pool

    # @return [Integer] Connection pool size (default: 10)
    attr_accessor :pool_size

    # @return [Integer] Connection pool timeout in seconds (default: 5)
    attr_accessor :pool_timeout

    # Establishes a connection pool for a Redis server.
    #
    # @param uri [String, URI, nil] The URI of the Redis server to connect to.
    #   If nil, uses the default URI from `@redis_uri_by_class` or `Familia.uri`.
    # @return [ConnectionPool] The connection pool for the Redis server.
    # @raise [ArgumentError] If no URI is specified.
    # @example
    #   Familia.connect('redis://localhost:6379')
    def connect(uri = nil)
      parsed_uri = URI.parse(uri) if uri.is_a?(String)
      parsed_uri ||= Familia.uri

      # Use server ID without DB for pooling (one pool per server)
      server_id = server_id_without_db(parsed_uri)
      conf = parsed_uri.conf
      @redis_uri_by_class[self] = server_id

      # Close existing pool if it exists
      # TODO: What is the benefit of closing the existing pool before
      # creating a new one? Seems disruptive if Familia.connect is
      # called multiple times (intentionally or accidentally). It should
      # probably just return the existing pool if it exists.
      @connection_pools[server_id].shutdown(&:close) if @connection_pools[server_id]

      # Create new connection pool
      @connection_pools[server_id] = if enable_connection_pool
        ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
          create_redis_connection(conf)
        end
      else
        # Fallback to direct connection for compatibility
        create_redis_connection(conf)
      end
    end

    # Retrieves a Redis connection from the appropriate pool.
    # Handles DB selection automatically based on the URI.
    #
    # @param uri [String, URI, Integer, nil] The URI of the Redis server or DB number.
    #   If nil, uses the default URI.
    # @return [Redis] The Redis client for the specified URI
    # @example
    #   Familia.redis('redis://localhost:6379/1')
    #   Familia.redis(2)  # Use DB 2 with default server
    def redis(uri = nil)
      target_uri = normalize_uri(uri)
      server_id = server_id_without_db(target_uri)
      target_db = target_uri.db

      # Ensure pool exists
      connect(target_uri) unless @connection_pools[server_id]

      pool_or_connection = @connection_pools[server_id]

      if enable_connection_pool && pool_or_connection.is_a?(ConnectionPool)
        # Use connection pool with DB selection
        get_pooled_connection(pool_or_connection, target_db)
      else
        # Direct connection (fallback mode)
        pool_or_connection.select(target_db) if target_db != pool_or_connection.current_database
        pool_or_connection
      end
    end

    # Sets the default URI for Redis connections.
    #
    # @param v [String, URI] The new default URI
    # @example
    #   Familia.uri = 'redis://localhost:6379'
    def uri=(val)
      @uri = val.is_a?(URI) ? val : URI.parse(val)
    end

    alias url uri
    alias url= uri=

    private

    # Creates a Redis connection with middleware configuration
    def create_redis_connection(conf)
      if Familia.enable_redis_logging
        RedisLogger.logger = Familia.logger
        RedisClient.register(RedisLogger)
      end

      if Familia.enable_redis_counter
        # NOTE: This middleware stays thread-safe with a mutex so it will
        # be a bottleneck when enabled in multi-threaded environments.
        RedisClient.register(RedisCommandCounter)
      end

      Redis.new(conf)
    end

    # Gets server ID without DB component for pool identification
    def server_id_without_db(uri)
      # Create a copy of URI without DB for server identification
      server_uri = uri.dup
      server_uri.db = nil
      server_uri.serverid
    end

    # Normalizes various URI formats to a consistent URI object
    def normalize_uri(uri)
      case uri
      when Integer
        # DB number with default server
        tmp = Familia.uri.dup
        tmp.db = uri
        tmp
      when String
        URI.parse(uri)
      when URI
        uri
      when nil
        Familia.uri
      else
        raise ArgumentError, "Invalid URI type: #{uri.class}"
      end
    end

    # Gets a connection from the pool with proper DB selection
    def get_pooled_connection(pool, target_db)
      if current_transaction_connection
        # Use existing transaction connection
        conn = current_transaction_connection
        ensure_db_selected(conn, target_db)
        conn
      else
        # Get connection from pool and select DB
        pool.with do |conn|
          ensure_db_selected(conn, target_db)
          yield conn if block_given?
          conn
        end
      end
    end

    # Ensures the connection is using the correct database
    def ensure_db_selected(connection, target_db)
      return unless target_db # TODO: Purpose?

      # Track current DB to avoid redundant SELECT calls
      # TODO: This is problematic. It should check the db from the redis connection
      # and not a variable we set that could be out of sync. The naming is also
      # confusing b/c it suggests that there is a "global" current DB.
      current_db = connection.instance_variable_get(:@familia_current_db)

      if current_db != target_db
        connection.select(target_db)
        connection.instance_variable_set(:@familia_current_db, target_db)
      end
    end

    # Returns the current transaction connection if in atomic block
    def current_transaction_connection
      Thread.current[:familia_current_transaction]
    end
  end
end
