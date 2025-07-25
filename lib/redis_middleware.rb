# lib/redis_middleware.rb

require 'concurrent-ruby'

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
#
# rubocop:disable ThreadSafety/ClassInstanceVariable
module RedisCommandCounter
  @count = Concurrent::AtomicFixnum.new(0)

  # We skip SELECT because depending on how the Familia is connecting to redis
  # the number of SELECT commands can be a lot or just a little. For example in
  # a configuration where there's a connection to each logical db, there's only
  # one when the connection is made. When using a provider of via thread local
  # it could theoretically double the number of statements executed.
  @skip_commands = Set.new(['SELECT']).freeze

  class << self
    # Gets the set of commands to skip counting.
    # @return [Set] The commands that won't be counted.
    attr_reader :skip_commands

    # Gets the current count of Redis commands executed.
    # @return [Integer] The number of Redis commands executed.
    def count
      @count.value
    end

    # Resets the command count to zero.
    # This method is thread-safe.
    # @return [Integer] The reset count (always 0).
    def reset
      @count.value = 0
    end

    # Increments the command count.
    # This method is thread-safe.
    # @return [Integer] The new count after incrementing.
    def increment
      @count.increment
    end

    def skip_command?(command)
      skip_commands.include?(command.first.to_s.upcase)
    end

    # Counts the number of Redis commands executed within a block.
    #
    # This method captures the command count before and after executing the
    # provided block, returning the difference. This is useful for measuring
    # how many Redis commands are executed by a specific operation.
    #
    # @yield [] The block of code to execute while counting commands.
    # @return [Integer] The number of Redis commands executed within the block.
    #
    # @example Count commands in a block
    #   commands_executed = RedisCommandCounter.count_commands do
    #     redis.set('key1', 'value1')
    #     redis.get('key1')
    #   end
    #   # commands_executed will be 2
    def count_commands
      start_count = count      # Capture the current command count before execution
      yield                    # Execute the provided block
      end_count = count        # Capture the command count after execution
      end_count - start_count  # Return the difference (commands executed in block)
    end
  end

  def klass
    RedisCommandCounter
  end

  # Counts the Redis command and delegates its execution.
  #
  # This method is called for each Redis command when the middleware is active.
  # It increments the command count (unless the command is in the skip list)
  # and then yields to execute the actual command.
  #
  # @param command [Array] The Redis command and its arguments.
  # @param redis_config [Hash] The configuration options for the Redis connection.
  # @return [Object] The result of the Redis command execution.
  def call(command, redis_config)
    klass.increment unless klass.skip_command?(command)
    yield
  end
end
# rubocop:enable ThreadSafety/ClassInstanceVariable
