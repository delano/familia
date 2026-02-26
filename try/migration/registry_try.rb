# try/migration/registry_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

Familia.debug = false

@redis = Familia.dbclient
@prefix = "familia:test:registry:#{Process.pid}:#{Familia.now.to_i}"
@registry = Familia::Migration::Registry.new(redis: @redis, prefix: @prefix)

# Clean any existing test keys
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }

# Mock migration classes for pending and status tests
# Using instance variables so they persist across test cases
@applied_migration = Class.new do
  def self.migration_id; 'test_migration_1'; end
end
@pending_migration = Class.new do
  def self.migration_id; 'test_migration_2'; end
end
@also_pending_migration = Class.new do
  def self.migration_id; 'test_migration_3'; end
end

## Registry class exists
Familia::Migration::Registry.is_a?(Class)
#=> true

## Registry initializes with correct prefix
@registry.prefix
#=> @prefix

## Registry initializes with provided redis client
@registry.redis == @redis
#=> true

## client method returns the redis client
@registry.client == @redis
#=> true

## applied? returns false for new migration
@registry.applied?('test_migration_1')
#=> false

## record_applied adds migration to applied set
@registry.record_applied('test_migration_1', { records_updated: 100 })
@registry.applied?('test_migration_1')
#=> true

## applied_at returns Time when applied
result = @registry.applied_at('test_migration_1')
result.is_a?(Time) && (Familia.now - result) < 5
#=> true

## applied_at returns nil when not applied
@registry.applied_at('nonexistent_migration')
#=> nil

## all_applied returns array with applied migrations
applied = @registry.all_applied
applied.is_a?(Array) && applied.any? { |h| h[:migration_id] == 'test_migration_1' }
#=> true

## all_applied entry contains applied_at timestamp
applied = @registry.all_applied
entry = applied.find { |h| h[:migration_id] == 'test_migration_1' }
entry[:applied_at].is_a?(Time)
#=> true

## metadata returns hash with correct status
meta = @registry.metadata('test_migration_1')
meta.is_a?(Hash) && meta[:status] == 'applied'
#=> true

## metadata contains keys_scanned from stats
meta = @registry.metadata('test_migration_1')
meta.key?(:keys_scanned)
#=> true

## metadata returns nil for unapplied migration
@registry.metadata('nonexistent_migration')
#=> nil

## pending filters out applied migrations
pending = @registry.pending([@applied_migration, @pending_migration])
pending.map(&:migration_id)
#=> ['test_migration_2']

## pending returns empty array when all are applied
@registry.record_applied('test_migration_2', {})
pending = @registry.pending([@applied_migration, @pending_migration])
pending
#=> []

## pending returns empty array for nil input
@registry.pending(nil)
#=> []

## pending returns empty array for empty input
@registry.pending([])
#=> []

## status returns combined info for all migrations
status = @registry.status([@applied_migration, @pending_migration, @also_pending_migration])
statuses = status.map { |s| [s[:migration_id], s[:status]] }.to_h
[statuses['test_migration_1'], statuses['test_migration_3']]
#=> [:applied, :pending]

## status entry includes applied_at for applied migrations
status = @registry.status([@applied_migration])
entry = status.first
entry[:applied_at].is_a?(Time)
#=> true

## status entry has nil applied_at for pending migrations
status = @registry.status([@also_pending_migration])
entry = status.first
entry[:applied_at]
#=> nil

## status returns empty array for nil input
@registry.status(nil)
#=> []

## record_rollback removes from applied set
@registry.record_rollback('test_migration_1')
@registry.applied?('test_migration_1')
#=> false

## record_rollback updates metadata to rolled_back status
meta = @registry.metadata('test_migration_1')
meta[:status]
#=> 'rolled_back'

## record_rollback adds rolled_back_at timestamp
meta = @registry.metadata('test_migration_1')
meta.key?(:rolled_back_at)
#=> true

## backup_field stores value in backup hash
@registry.backup_field('backup_test', 'some:key', 'field1', 'original_value')
backup_key = "#{@prefix}:backup:backup_test"
@redis.hget(backup_key, 'some:key:field1')
#=> 'original_value'

## backup key has TTL set
ttl = @redis.ttl("#{@prefix}:backup:backup_test")
ttl > 0 && ttl <= Familia::Migration.config.backup_ttl
#=> true

## restore_backup returns count of restored fields
@redis.del('some:key')
@redis.hset('some:key', 'field1', 'modified_value')
count = @registry.restore_backup('backup_test')
count >= 1
#=> true

## restore_backup restores correct value
@redis.hget('some:key', 'field1')
#=> 'original_value'

## restore_backup returns 0 when no backup exists
@registry.restore_backup('nonexistent_backup')
#=> 0

## clear_backup removes backup data
@registry.clear_backup('backup_test')
@redis.exists("#{@prefix}:backup:backup_test")
#=> 0

## record_applied works with class that has migration_id
@class_migration = Class.new do
  def self.migration_id; 'class_based_migration'; end
end
@registry.record_applied(@class_migration, {})
@registry.applied?('class_based_migration')
#=> true

## record_applied works with instance whose class has migration_id
@instance_migration_class = Class.new do
  def self.migration_id; 'instance_based_migration'; end
end
instance = @instance_migration_class.new
@registry.record_applied(instance, { duration_ms: 150 })
@registry.applied?('instance_based_migration')
#=> true

## record_applied stores duration_ms in metadata
meta = @registry.metadata('instance_based_migration')
meta[:duration_ms]
#=> 150

# Teardown
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
@redis.del('some:key')
