# frozen_string_literal: true

require_relative '../../lib/redis_middleware'

#
module Familia
  @uri = URI.parse 'redis://127.0.0.1'
  @redis_clients = {}
  @redis_uri_by_class = {}

  # The Connection module provides Redis connection management for Familia.
  # It allows easy setup and access to Redis clients across different URIs.
  module Connection
    # @return [Hash] A hash of Redis clients, keyed by server ID
    attr_reader :redis_clients

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
      uri = URI.parse(uri) if uri.is_a?(String)
      uri ||= @redis_uri_by_class[self]
      uri ||= Familia.uri

      raise ArgumentError, 'No URI specified' unless uri

      conf = uri.conf
      @redis_uri_by_class[self] = uri.serverid

      if Familia.enable_redis_logging
        RedisLogger.logger = Familia.logger
        RedisClient.register(RedisLogger)
      end

      if Familia.enable_redis_counter
        # NOTE: This middleware stays thread-safe with a mutex so it will
        # be a bottleneck when enabled in multi-threaded environments.
        RedisClient.register(RedisCommandCounter)
      end

      redis = Redis.new(conf)

      # Close the existing connection if it exists
      @redis_clients[uri.serverid].close if @redis_clients[uri.serverid]
      @redis_clients[uri.serverid] = redis
    end

    # Retrieves or creates a Redis client for the given URI.
    #
    # @param uri [String, URI, nil] The URI of the Redis server.
    #   If nil, uses the default URI.
    # @return [Redis] The Redis client for the specified URI
    # @example
    #   Familia.redis('redis://localhost:6379')
    def redis(uri = nil)
      if uri.is_a?(Integer)
        tmp = Familia.uri
        tmp.db = uri
        uri = tmp
      elsif uri.is_a?(String)
        uri &&= URI.parse uri
      end
      uri ||= Familia.uri
      connect(uri) unless @redis_clients[uri.serverid]
      @redis_clients[uri.serverid]
    end

    # Retrieves the Redis client associated with the given class.
    #
    # @param klass [Class] The class for which to retrieve the Redis client.
    # @return [Redis] The Redis client associated with the given class.
    def redis_uri_by_class(klass)
      uri = @redis_uri_by_class[klass]
      connect(uri)
    end

    # Sets the default URI for Redis connections.
    #
    # @param v [String, URI] The new default URI
    # @example
    #   Familia.uri = 'redis://localhost:6379'
    def uri=(val)
      @uri = val.is_a?(URI) ? v : URI.parse(val)
    end

    alias url uri
    alias url= uri=
  end
end
