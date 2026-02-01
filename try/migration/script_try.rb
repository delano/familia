# try/migration/script_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration/errors'
require_relative '../../lib/familia/migration/script'

Familia.debug = false

@redis = Familia.dbclient
@test_prefix = "familia:test:script:#{Process.pid}"

## Script class exists
Familia::Migration::Script.is_a?(Class)
#=> true

## Built-in scripts are registered
Familia::Migration::Script.scripts.keys.sort
#=> [:backup_and_modify_field, :copy_field, :delete_field, :rename_field, :rename_key_preserve_ttl]

## registered? returns true for built-in scripts
Familia::Migration::Script.registered?(:rename_field)
#=> true

## registered? returns false for unknown scripts
Familia::Migration::Script.registered?(:nonexistent_script)
#=> false

## sha_for returns SHA1 hash for registered script
sha = Familia::Migration::Script.sha_for(:rename_field)
sha.is_a?(String) && sha.length == 40
#=> true

## sha_for returns nil for unregistered script
Familia::Migration::Script.sha_for(:no_such_script)
#=> nil

## Custom script can be registered
Familia::Migration::Script.register(:test_script, "return 'hello'")
Familia::Migration::Script.registered?(:test_script)
#=> true

## register raises ArgumentError for non-Symbol name
begin
  Familia::Migration::Script.register("string_name", "return 1")
  false
rescue ArgumentError => e
  e.message.include?('Symbol')
end
#=> true

## register raises ArgumentError for empty source
begin
  Familia::Migration::Script.register(:empty_script, "   ")
  false
rescue ArgumentError => e
  e.message.include?('empty')
end
#=> true

## rename_field script works correctly
@redis.del("#{@test_prefix}:hash1")
@redis.hset("#{@test_prefix}:hash1", "old_name", "test_value")
result = Familia::Migration::Script.execute(
  @redis,
  :rename_field,
  keys: ["#{@test_prefix}:hash1"],
  argv: ["old_name", "new_name"]
)
[@redis.hexists("#{@test_prefix}:hash1", "old_name"),
 @redis.hget("#{@test_prefix}:hash1", "new_name"),
 result]
#=> [false, "test_value", 1]

## rename_field returns 0 when source field does not exist
@redis.del("#{@test_prefix}:hash1a")
@redis.hset("#{@test_prefix}:hash1a", "other_field", "value")
result = Familia::Migration::Script.execute(
  @redis,
  :rename_field,
  keys: ["#{@test_prefix}:hash1a"],
  argv: ["missing_field", "new_field"]
)
result
#=> 0

## copy_field script works correctly
@redis.del("#{@test_prefix}:hash2")
@redis.hset("#{@test_prefix}:hash2", "source", "copied_value")
Familia::Migration::Script.execute(
  @redis,
  :copy_field,
  keys: ["#{@test_prefix}:hash2"],
  argv: ["source", "destination"]
)
[@redis.hget("#{@test_prefix}:hash2", "source"),
 @redis.hget("#{@test_prefix}:hash2", "destination")]
#=> ["copied_value", "copied_value"]

## copy_field returns 0 when source field does not exist
@redis.del("#{@test_prefix}:hash2a")
result = Familia::Migration::Script.execute(
  @redis,
  :copy_field,
  keys: ["#{@test_prefix}:hash2a"],
  argv: ["missing", "destination"]
)
result
#=> 0

## delete_field script works correctly
@redis.del("#{@test_prefix}:hash3")
@redis.hset("#{@test_prefix}:hash3", "to_delete", "value")
result = Familia::Migration::Script.execute(
  @redis,
  :delete_field,
  keys: ["#{@test_prefix}:hash3"],
  argv: ["to_delete"]
)
[result, @redis.hexists("#{@test_prefix}:hash3", "to_delete")]
#=> [1, false]

## delete_field returns 0 when field does not exist
@redis.del("#{@test_prefix}:hash3a")
result = Familia::Migration::Script.execute(
  @redis,
  :delete_field,
  keys: ["#{@test_prefix}:hash3a"],
  argv: ["nonexistent"]
)
result
#=> 0

## rename_key_preserve_ttl works and preserves TTL
@redis.del("#{@test_prefix}:src_key", "#{@test_prefix}:dst_key")
@redis.set("#{@test_prefix}:src_key", "value")
@redis.expire("#{@test_prefix}:src_key", 3600)
Familia::Migration::Script.execute(
  @redis,
  :rename_key_preserve_ttl,
  keys: ["#{@test_prefix}:src_key", "#{@test_prefix}:dst_key"],
  argv: []
)
ttl = @redis.ttl("#{@test_prefix}:dst_key")
[@redis.exists("#{@test_prefix}:src_key"),
 @redis.get("#{@test_prefix}:dst_key"),
 ttl > 3500]
#=> [0, "value", true]

## backup_and_modify_field backs up and modifies correctly
@redis.del("#{@test_prefix}:hash4", "#{@test_prefix}:backup")
@redis.hset("#{@test_prefix}:hash4", "myfield", "original_value")
old_val = Familia::Migration::Script.execute(
  @redis,
  :backup_and_modify_field,
  keys: ["#{@test_prefix}:hash4", "#{@test_prefix}:backup"],
  argv: ["myfield", "new_value", "3600"]
)
[@redis.hget("#{@test_prefix}:hash4", "myfield"),
 @redis.hget("#{@test_prefix}:backup", "#{@test_prefix}:hash4:myfield"),
 old_val]
#=> ["new_value", "original_value", "original_value"]

## ScriptNotFound raised for unregistered script
begin
  Familia::Migration::Script.execute(@redis, :no_such_script, keys: [], argv: [])
  false
rescue Familia::Migration::Script::ScriptNotFound
  true
end
#=> true

## ScriptEntry is immutable (frozen)
entry = Familia::Migration::Script.scripts[:rename_field]
[entry.source.frozen?, entry.sha.frozen?]
#=> [true, true]

## preload_all returns map of script names to SHAs
result = Familia::Migration::Script.preload_all(@redis)
result.is_a?(Hash) && result.key?(:rename_field) && result[:rename_field].length == 40
#=> true

## reset! restores only built-in scripts
Familia::Migration::Script.register(:temp_script, "return 1")
Familia::Migration::Script.reset!
[Familia::Migration::Script.registered?(:temp_script),
 Familia::Migration::Script.registered?(:rename_field)]
#=> [false, true]

# Teardown
@redis.keys("#{@test_prefix}:*").each { |k| @redis.del(k) }
