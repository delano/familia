# frozen_string_literal: true

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

# RedisCommandCounter is RedisClient middleware.
#
# This middleware counts the number of Redis commands executed. It can be
# useful for performance monitoring and debugging, allowing you to track
# the volume of Redis operations in your application.
#
# @example Enable Redis command counting
#   RedisCommandCounter.reset
#   RedisClient.register(RedisCommandCounter)
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
module RedisCommandCounter
  @count = 0
  @mutex = Mutex.new

  class << self
    # Gets the current count of Redis commands executed.
    # @return [Integer] The number of Redis commands executed.
    attr_reader :count

    # Resets the command count to zero.
    # This method is thread-safe.
    # @return [Integer] The reset count (always 0).
    def reset
      @mutex.synchronize { @count = 0 }
    end

    # Increments the command count.
    # This method is thread-safe.
    # @return [Integer] The new count after incrementing.
    def increment
      @mutex.synchronize { @count += 1 }
    end

    def count_commands
      start_count = count
      yield
      end_count = count
      end_count - start_count
    end
  end

  # Counts the Redis command and delegates its execution.
  #
  # This method is called for each Redis command when the middleware is active.
  # It increments the command count and then yields to execute the actual command.
  #
  # @param command [Array] The Redis command and its arguments.
  # @param redis_config [Hash] The configuration options for the Redis connection.
  # @return [Object] The result of the Redis command execution.
  def call(command, redis_config)
    RedisCommandCounter.increment
    yield
  end
end
