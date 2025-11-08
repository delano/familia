#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for logger lazy initialization
#
# Tests concurrent logger access to ensure that only a single logger
# instance is created even under high concurrent load.
#
# These tests verify:
# 1. Concurrent logger initialization (default logger)
# 2. Logger singleton property
# 3. Maximum contention with CyclicBarrier pattern
# 4. Custom logger setter thread safety

## Concurrent logger initialization with 50 threads
# Reset the logger and mutex to simulate first access
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

barrier = Concurrent::CyclicBarrier.new(50)
loggers = Concurrent::Array.new

threads = 50.times.map do
  Thread.new do
    barrier.wait
    # Get the logger instance
    logger = Familia.logger
    loggers << logger.object_id
  end
end

threads.each(&:join)

# All threads should get the same logger instance
[loggers.any?(nil), loggers.uniq.size, loggers.size]
#=> [false, 1, 50]


## Logger is instance of FamiliaLogger
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

logger = Familia.logger
logger.class.name
#=> 'Familia::FamiliaLogger'


## Logger has correct progname set
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

logger = Familia.logger
logger.progname
#=> 'Familia'


## Logger has correct formatter set
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

logger = Familia.logger
logger.formatter.class.name
#=> 'Familia::LogFormatter'


## Maximum contention with concurrent logging operations
# Reset logger and test actual logging under concurrent load
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

barrier = Concurrent::CyclicBarrier.new(50)
logger_ids = Concurrent::Array.new
errors = Concurrent::Array.new

threads = 50.times.map do |i|
  Thread.new do
    begin
      barrier.wait
      # Each thread logs a message
      logger = Familia.logger
      logger_ids << logger.object_id

      # Capture output to avoid cluttering test output
      original_stderr = $stderr
      $stderr = StringIO.new
      logger.info "Thread #{i} logging"
      $stderr = original_stderr
    rescue => e
      errors << e.message
    end
  end
end

threads.each(&:join)

# All threads should use same logger instance and have no errors
[logger_ids.uniq.size, errors.empty?]
#=> [1, true]


## Custom logger setter clears atomic reference
# Set a custom logger
custom_logger = Logger.new($stderr)
custom_logger.progname = 'CustomApp'

Familia.logger = custom_logger

# Getting logger should return the custom one
retrieved_logger = Familia.logger
[retrieved_logger.object_id == custom_logger.object_id, retrieved_logger.progname]
#=> [true, 'CustomApp']


## Setting logger multiple times is thread-safe
# Reset to default logger first
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)
Familia.logger  # Initialize default

barrier = Concurrent::CyclicBarrier.new(20)
final_loggers = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    # Half threads set new logger, half read
    if i.even?
      custom = Logger.new($stderr)
      custom.progname = "Thread#{i}"
      Familia.logger = custom
    else
      final_loggers << Familia.logger.object_id
    end
  end
end

threads.each(&:join)

# After concurrent setter/getter operations, logger should still be valid
final_logger = Familia.logger
final_logger.class
#=> Logger


## Rapid sequential access maintains singleton
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

logger_ids = []
100.times do
  logger_ids << Familia.logger.object_id
end

logger_ids.uniq.size
#=> 1


## Mutex is used for thread safety
Familia.instance_variable_set(:@logger, nil)
Familia.instance_variable_set(:@logger_mutex, nil)

# Trigger lazy initialization
Familia.logger

# Should have created a Mutex for synchronization
mutex = Familia.instance_variable_get(:@logger_mutex)
mutex.class.name
#=> 'Thread::Mutex'
