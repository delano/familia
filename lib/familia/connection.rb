# frozen_string_literal: true

module Familia
  @uri = URI.parse 'redis://127.0.0.1'
  @redis_clients = {}

  # The Connection module provides Redis connection management for Familia.
  # It allows easy setup and access to Redis clients across different URIs.
  module Connection
    # @return [Hash] A hash of Redis clients, keyed by server ID
    attr_reader :redis_clients

    # @return [URI] The default URI for Redis connections
    attr_reader :uri

    # @return [Boolean] Whether Redis logging is enabled
    attr_accessor :enable_redis_logging

    # Establishes a connection to a Redis server.
    #
    # @param uri [String, URI, nil] The URI of the Redis server to connect to.
    #   If nil, uses the default URI.
    # @return [Redis] The connected Redis client
    # @example
    #   Familia.connect('redis://localhost:6379')
    def connect(uri = nil)
      uri = URI.parse(uri) if uri.is_a?(String)
      uri ||= Familia.uri

      raise ArgumentError, 'No URI specified' unless uri

      conf = uri.conf

      if Familia.enable_redis_logging
        RedisLogger.logger = Familia.logger
        RedisClient.register(RedisLogger)
      end

      conf = conf.merge({}) if Familia.logger

      redis = Redis.new(conf)
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
      p [1, uri]
      uri = URI.parse(uri) if uri.is_a?(String)
      p [2, uri]
      uri ||= Familia.uri
      p [3, uri]

      raise ArgumentError, "No URI specified (#{Familia.uri})" unless uri

      connect(uri) unless @redis_clients[uri.serverid]
      @redis_clients[uri.serverid]
    end

    # Sets the default URI for Redis connections.
    #
    # @param v [String, URI] The new default URI
    # @example
    #   Familia.uri = 'redis://localhost:6379'
    def uri=(v)
      @uri = v.is_a?(URI) ? v : URI.parse(v)
    end

    alias url uri
    alias url= uri=
  end
end

# RedisLogger is RedisClient middleware.
#
# This middleware addresses the need for detailed Redis command logging, which
# was removed from the redis-rb gem due to performance concerns. However, in
# many development and debugging scenarios, the ability to log Redis commands
# can be invaluable.
#
# @example Enable Redis command logging
#   RedisLogger.logger = Logger.new(STDOUT)
#   RedisClient.register(RedisLogger)
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
#
# @note While there were concerns about the performance impact of logging in
#   the redis-rb gem, this middleware is designed to be optional and can be
#   easily enabled or disabled as needed. The performance impact is minimal
#   when logging is disabled, and the benefits during development and debugging
#   often outweigh the slight performance cost when enabled.
module RedisLogger
  @logger = nil

  class << self
    # Gets/sets the logger instance used by RedisLogger.
    # @return [Logger, nil] The current logger instance or nil if not set.
    attr_accessor :logger
  end

  # Logs the Redis command and its execution time.
  #
  # This method is called for each Redis command when the middleware is active.
  # It logs the command and its execution time only if a logger is set.
  #
  # @param command [Array] The Redis command and its arguments.
  # @param redis_config [Hash] The configuration options for the Redis
  #   connection.
  # @return [Object] The result of the Redis command execution.
  #
  # @note The performance impact of this logging is negligible when no logger
  #   is set, as it quickly returns control to the Redis client. When a logger
  #   is set, the minimal overhead is often offset by the valuable insights
  #   gained during development and debugging.
  def call(command, redis_config)
    return yield unless RedisLogger.logger

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    result = yield
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
    RedisLogger.logger.debug("Redis: #{command.inspect} (#{duration}µs)")
    result
  end
end
