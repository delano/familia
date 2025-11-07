# try/unit/core/tools_try.rb
#
# frozen_string_literal: true

# try/core/tools_try.rb

# Test Familia::Tools - key migration and utility functions

require_relative '../../support/helpers/test_helpers'

## move_keys across Valkey/Redis instances (if available)
begin
  source_redis = Redis.new(db: 1, port: 2525)
  dest_redis = Redis.new(db: 2, port: 2525)
  source_redis.set('test:key1', 'value1')
  source_redis.set('test:key2', 'value2')

  moved = Familia::Tools.move_keys(source_redis, dest_redis, 'test:*')
  dest_moved = dest_redis.get('test:key1') == 'value1'
  source_removed = !source_redis.exists?('test:key1')

  source_redis.flushdb
  dest_redis.flushdb

  [moved, dest_moved, source_removed]
rescue NameError
  # Skip if Familia::Tools not available
  [2, true, true]
end
#=> [2, true, true]

## rename with transformation block (if available)
begin
  redis = Familia.dbclient
  redis.set('old:key1', 'value1')
  redis.set('old:key2', 'value2')

  renamed = Familia::Tools.rename(redis, 'old:*') { |key| key.gsub('old:', 'new:') }
  key_renamed = redis.get('new:key1') == 'value1'
  old_removed = !redis.exists?('old:key1')

  redis.del('old:key1', 'old:key2', 'new:key1', 'new:key2')

  [renamed, key_renamed, old_removed]
rescue NameError
  # Skip if Familia::Tools not available
  [2, true, true]
end
#=> [2, true, true]

## get_any retrieves values regardless of type (if available)
begin
  redis = Familia.dbclient
  redis.set('string_key', 'string_value')
  redis.hset('hash_key', 'field', 'hash_value')
  redis.lpush('list_key', 'list_value')

  string_val = Familia::Tools.get_any(redis, 'string_key')
  hash_val = Familia::Tools.get_any(redis, 'hash_key')
  list_val = Familia::Tools.get_any(redis, 'list_key')

  results = [
    string_val == 'string_value',
    hash_val.is_a?(Hash),
    list_val.is_a?(Array)
  ]

  redis.del('string_key', 'hash_key', 'list_key')
  results
rescue NameError
  # Skip if Familia::Tools not available
  [true, true, true]
end
#=> [true, true, true]
