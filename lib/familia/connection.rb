# rubocop:disable all


#
module Familia

  @uri = URI.parse 'redis://127.0.0.1'
  @redis_clients = {}
  @enable_redis_logging = false

  module Connection

    attr_reader :redis_clients, :uri
    attr_accessor :enable_redis_logging

    def connect(uri = nil)
      uri &&= URI.parse uri if uri.is_a?(String)
      uri ||= Familia.uri

      conf = uri.conf

      #Familia.trace(:CONNECT, nil, conf.inspect, caller(1...3))

      if Familia.enable_redis_logging
        RedisLogger.logger = Familia.logger
        RedisClient.register(RedisLogger)
      end

      conf = conf.merge({}) if Familia.logger

      redis = Redis.new conf

      @redis_clients[uri.serverid] = redis
    end

    def redis(uri = nil)
      uri &&= URI.parse(uri)
      uri ||= Familia.uri

      connect(uri) unless @redis_clients[uri.serverid]
      @redis_clients[uri.serverid]
    end

    def uri=(v)
      v = URI.parse v unless URI === v
      @uri = v
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
