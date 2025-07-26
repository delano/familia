require_relative '../helpers/test_helpers'

# Test Familia::Tools - key migration and utility functions
group "Familia::Tools"

try "move_keys across Redis instances" do
  source_redis = Redis.new(db: 10)
  dest_redis = Redis.new(db: 11)

  # Setup test data
  source_redis.set("test:key1", "value1")
  source_redis.set("test:key2", "value2")

  # Move keys
  moved = Familia::Tools.move_keys(source_redis, dest_redis, "test:*")

  moved == 2 &&
    dest_redis.get("test:key1") == "value1" &&
    !source_redis.exists?("test:key1")
ensure
  source_redis&.flushdb
  dest_redis&.flushdb
end

try "rename with transformation block" do
  redis = Familia.redis
  redis.set("old:key1", "value1")
  redis.set("old:key2", "value2")

  renamed = Familia::Tools.rename(redis, "old:*") { |key| key.gsub("old:", "new:") }

  renamed == 2 &&
    redis.get("new:key1") == "value1" &&
    !redis.exists?("old:key1")
ensure
  redis&.del("old:key1", "old:key2", "new:key1", "new:key2")
end

try "get_any retrieves values regardless of type" do
  redis = Familia.redis
  redis.set("string_key", "string_value")
  redis.hset("hash_key", "field", "hash_value")
  redis.lpush("list_key", "list_value")

  string_val = Familia::Tools.get_any(redis, "string_key")
  hash_val = Familia::Tools.get_any(redis, "hash_key")
  list_val = Familia::Tools.get_any(redis, "list_key")

  string_val == "string_value" &&
    hash_val.is_a?(Hash) &&
    list_val.is_a?(Array)
ensure
  redis&.del("string_key", "hash_key", "list_key")
end
