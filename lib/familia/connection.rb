# frozen_string_literal: true

require_relative '../../lib/redis_middleware'

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

    # @return [Boolean] Whether Redis command logging is enabled
    attr_accessor :enable_redis_logging

    # @return [Boolean] Whether Redis command counter is enabled
    attr_accessor :enable_redis_counter

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

      if Familia.enable_redis_logging
        RedisLogger.logger = Familia.logger
        RedisClient.register(RedisLogger)
      end

      if Familia.enable_redis_counter
        # NOTE: This middleware stays thread-safe with a mutex so it will
        # be a bottleneck when enabled in multi-threaded environments.
        RedisClient.register(RedisCommandCounter)
      end

      redis = Redis.new(parsed_uri.conf)

      if @redis_clients.key?(serverid)
        msg = "Overriding existing connection for #{serverid}"
        Familia.warn(msg)
      end

      @redis_clients[uri.serverid] = redis
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
    def redis(*)
      if Thread.current.key?(:familia_connection)
        Thread.current[:familia_connection]
      else
        @redis ||= connect(*)
      end
    end

    # Sets the default URI for Redis connections.
    #
    # NOTE: uri is not a property of the Settings module b/c it's not
    # configured in class defintions like ttl or logical DB index.
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

    # Normalizes various URI formats to a consistent URI object
    def normalize_uri(uri)
      case uri
      when Integer
        # DB number with default server
        familia_uri = Familia.uri.dup
        familia_uri.db = uri
        familia_uri
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
end
end
