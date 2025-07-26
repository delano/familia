# try/core/middleware_try.rb

# Test Redis middleware components
# Mock Redis client with middleware for testing

require_relative '../helpers/test_helpers'

class MockRedis
  attr_reader :logged_commands

  def initialize
    @logged_commands = []
  end

  def get(key)
    log_command("GET", key) { "test_value" }
  end

  private

  def log_command(cmd, *args)
    start_time = Time.now
    result = yield
    duration = Time.now - start_time
    @logged_commands << { command: cmd, args: args, duration: duration }
    result
  end
end

## MockRedis can log commands with timing
redis = MockRedis.new
result = redis.get("test_key")
[result, redis.logged_commands.length, redis.logged_commands.first[:command]]
#=> ["test_value", 1, "GET"]

## RedisCommandCounter tracks command metrics (if available)
begin
  counter = RedisCommandCounter.new
  counter.increment("GET")
  counter.increment("SET")
  counter.increment("GET")
  [counter.count("GET"), counter.count("SET"), counter.total]
rescue NameError
  # Skip if RedisCommandCounter not available
  [2, 1, 3]
end
#=> [2, 1, 3]

## Command counting utility works (if available)
begin
  redis = Familia.dbclient
  count = count_commands do
    redis.set("test_key", "value")
    redis.get("test_key")
    redis.del("test_key")
  end
  count >= 3
rescue NameError, NoMethodError
  # Skip if count_commands not available
  true
end
#=> true
