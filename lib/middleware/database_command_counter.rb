# lib/middleware/database_command_counter.rb

require 'concurrent-ruby'

# DatabaseCommandCounter is RedisClient middleware for counting commands.
#
# This middleware counts the number of Redis commands executed. It can be
# useful for performance monitoring and debugging, allowing you to track
# the volume of Redis operations in your application.
#
# ## Middleware Chaining
#
# This middleware works correctly alongside DatabaseLogger because it uses
# `super` to properly chain method calls. See {DatabaseLogger} for detailed
# explanation of middleware chaining mechanics.
#
# @example Enable Redis command counting
#   DatabaseCommandCounter.reset
#   RedisClient.register(DatabaseCommandCounter)
#
# @example Use with DatabaseLogger
#   RedisClient.register(DatabaseLogger)
#   RedisClient.register(DatabaseCommandCounter)
#   # Both middlewares execute correctly in sequence
#
# @see https://github.com/redis-rb/redis-client?tab=readme-ov-file#instrumentation-and-middlewares
# @see DatabaseLogger For middleware chain architecture details
#
module DatabaseCommandCounter
  @count = Concurrent::AtomicFixnum.new(0)

  # Commands to skip when counting.
  #
  # We skip SELECT because the frequency depends on connection architecture:
  # - Connection-per-database: Only one SELECT when connection is made
  # - Provider/thread-local: Could theoretically double statement count
  #
  # @return [Set<String>] Commands that won't be counted
  @skip_commands = ::Set.new(['SELECT']).freeze

  class << self
    # Gets the set of commands to skip counting.
    # @return [Set<String>] The commands that won't be counted
    attr_reader :skip_commands

    # Gets the current count of Redis commands executed.
    # @return [Integer] The number of Redis commands executed
    def count
      @count.value
    end

    # Resets the command count to zero.
    # This method is thread-safe.
    # @return [Integer] The reset count (always 0)
    def reset
      @count.value = 0
    end

    # Increments the command count.
    # This method is thread-safe.
    # @return [Integer] The new count after incrementing
    # @api private
    def increment
      @count.increment
    end

    # Checks if a command should be skipped.
    # @param command [Array] The Redis command array
    # @return [Boolean] true if command should be skipped
    # @api private
    def skip_command?(command)
      skip_commands.include?(command.first.to_s.upcase)
    end

    # Counts the number of Redis commands executed within a block.
    #
    # This method captures the command count before and after executing the
    # provided block, returning the difference. This is useful for measuring
    # how many Redis commands are executed by a specific operation.
    #
    # @yield [] The block of code to execute while counting commands
    # @return [Integer] The number of Redis commands executed within the block
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

  # Reference to the module for use in instance methods
  # @api private
  def klass
    DatabaseCommandCounter
  end

  # Counts the Redis command and delegates its execution.
  #
  # This method is part of the RedisClient middleware chain. It MUST use `super`
  # instead of `yield` to properly chain with other middlewares like DatabaseLogger.
  #
  # @param command [Array] The Redis command and its arguments
  # @param _config [RedisClient::Config, Hash] Connection configuration (unused)
  # @return [Object] The result of the Redis command execution
  def call(command, _config)
    klass.increment unless klass.skip_command?(command)
    super  # CRITICAL: Must use super, not yield, to chain middlewares
  end

  # Counts commands in a pipeline and delegates execution.
  #
  # @param commands [Array<Array>] Array of command arrays
  # @param _config [RedisClient::Config, Hash] Connection configuration (unused)
  # @return [Array] Results from pipelined commands
  def call_pipelined(commands, _config)
    # Count all commands in the pipeline (except skipped ones)
    commands.each do |command|
      klass.increment unless klass.skip_command?(command)
    end
    super  # CRITICAL: Must use super, not yield, to chain middlewares
  end

  # Counts a call_once command and delegates execution.
  #
  # @param command [Array] The Redis command and its arguments
  # @param _config [RedisClient::Config, Hash] Connection configuration (unused)
  # @return [Object] The result of the Redis command execution
  def call_once(command, _config)
    klass.increment unless klass.skip_command?(command)
    super  # CRITICAL: Must use super, not yield, to chain middlewares
  end
end
