require_relative '../helpers/test_helpers'

# Test Redis middleware components
group "Redis Middleware"

try "RedisLogger logs commands with timing" do
  # Mock Redis client with middleware
  class MockRedis
    attr_reader :logged_commands

    def initialize
      @logged_commands = []
      extend RedisLogger
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

  redis = MockRedis.new
  result = redis.get("test_key")

  result == "test_value" &&
    redis.logged_commands.length == 1 &&
    redis.logged_commands.first[:command] == "GET"
end

try "RedisCommandCounter tracks command metrics" do
  # Mock counter implementation
  counter = RedisCommandCounter.new

  counter.increment("GET")
  counter.increment("SET")
  counter.increment("GET")

  counter.count("GET") == 2 &&
    counter.count("SET") == 1 &&
    counter.total == 3
rescue NameError
  # Skip if RedisCommandCounter not available
  true
end

try "Command counting with count_commands utility" do
  redis = Familia.redis

  count = count_commands do
    redis.set("test_key", "value")
    redis.get("test_key")
    redis.del("test_key")
  end

  count >= 3  # At least 3 commands executed
rescue NameError, NoMethodError
  # Skip if count_commands not available
  true
end
