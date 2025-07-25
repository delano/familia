# lib/middleware/database_middleware.rb

require 'concurrent-ruby'

# DatabaseLogger is RedisClient middleware.
#
# This middleware addresses the need for detailed Database command logging, which
# was removed from the redis-rb gem due to performance concerns. However, in
# many development and debugging scenarios, the ability to log Database commands
# can be invaluable.
#
# @example Enable Database command logging
#   DatabaseLogger.logger = Logger.new(STDOUT)
#   RedisClient.register(DatabaseLogger)
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
#
# @note While there were concerns about the performance impact of logging in
#   the redis-rb gem, this middleware is designed to be optional and can be
#   easily enabled or disabled as needed. The performance impact is minimal
#   when logging is disabled, and the benefits during development and debugging
#   often outweigh the slight performance cost when enabled.
module DatabaseLogger
  @logger = nil

  class << self
    # Gets/sets the logger instance used by DatabaseLogger.
    # @return [Logger, nil] The current logger instance or nil if not set.
    attr_accessor :logger
  end

  # Logs the Database command and its execution time.
  #
  # This method is called for each Database command when the middleware is active.
  # It logs the command and its execution time only if a logger is set.
  #
  # @param command [Array] The Database command and its arguments.
  # @param _config [Hash] The configuration options for the Redis
  #   connection.
  # @return [Object] The result of the Database command execution.
  #
  # @note The performance impact of this logging is negligible when no logger
  #   is set, as it quickly returns control to the Database client. When a logger
  #   is set, the minimal overhead is often offset by the valuable insights
  #   gained during development and debugging.
  def call(command, _config)
    return yield unless DatabaseLogger.logger

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
    result = yield
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
    DatabaseLogger.logger.debug("Redis: #{command.inspect} (#{duration}µs)")
    result
  end
end

# DatabaseCommandCounter is RedisClient middleware.
#
# This middleware counts the number of Database commands executed. It can be
# useful for performance monitoring and debugging, allowing you to track
# the volume of Database operations in your application.
#
# @example Enable Database command counting
#   DatabaseCommandCounter.reset
#   RedisClient.register(DatabaseCommandCounter)
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
#
# rubocop:disable ThreadSafety/ClassInstanceVariable
module DatabaseCommandCounter
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

    # Gets the current count of Database commands executed.
    # @return [Integer] The number of Database commands executed.
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

    # Counts the number of Database commands executed within a block.
    #
    # This method captures the command count before and after executing the
    # provided block, returning the difference. This is useful for measuring
    # how many Database commands are executed by a specific operation.
    #
    # @yield [] The block of code to execute while counting commands.
    # @return [Integer] The number of Database commands executed within the block.
    #
    # @example Count commands in a block
    #   commands_executed = DatabaseCommandCounter.count_commands do
    #     dbclient.set('key1', 'value1')
    #     dbclient.get('key1')
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
    DatabaseCommandCounter
  end

  # Counts the Database command and delegates its execution.
  #
  # This method is called for each Database command when the middleware is active.
  # It increments the command count (unless the command is in the skip list)
  # and then yields to execute the actual command.
  #
  # @param command [Array] The Database command and its arguments.
  # @param _config [Hash] The configuration options for the Database connection.
  # @return [Object] The result of the Database command execution.
  def call(command, _config)
    klass.increment unless klass.skip_command?(command)
    yield
  end
end
# rubocop:enable ThreadSafety/ClassInstanceVariable
