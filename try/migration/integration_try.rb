# try/migration/integration_try.rb
#
# Integration tests for complete migration workflow scenarios
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

Familia.debug = false

# Setup - unique prefix for this test run
@redis = Familia.dbclient
@prefix = "familia:test:integration:#{Process.pid}:#{Time.now.to_i}"
@registry = Familia::Migration::Registry.new(redis: @redis, prefix: @prefix)

# Store initial migrations
@initial_migrations = Familia::Migration.migrations.dup

# Helper to reset state
def reset_state
  @redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
end

reset_state

# ============================================
# Define all migration classes upfront
# ============================================

# Scenario 1: Simple migration lifecycle
class IntegrationSimpleMigration < Familia::Migration::Base
  self.migration_id = 'integration_simple'
  self.description = 'Simple integration test'

  class << self
    attr_accessor :ran_count
  end
  self.ran_count = 0

  def migration_needed?
    self.class.ran_count < 1
  end

  def migrate
    self.class.ran_count += 1
    track_stat(:executed)
  end
end

# Scenario 2: Migration with dependencies
class IntegrationDepA < Familia::Migration::Base
  self.migration_id = 'integration_dep_a'
  self.dependencies = []

  class << self
    attr_accessor :order
  end
  self.order = []

  def migration_needed?; true; end
  def migrate
    self.class.order << :a
  end
end

class IntegrationDepB < Familia::Migration::Base
  self.migration_id = 'integration_dep_b'
  self.dependencies = ['integration_dep_a']

  def migration_needed?; true; end
  def migrate
    IntegrationDepA.order << :b
  end
end

# Scenario 3: Dry run mode
class IntegrationDryRun < Familia::Migration::Base
  self.migration_id = 'integration_dry'

  class << self
    attr_accessor :executed
  end
  self.executed = false

  def migration_needed?; true; end
  def migrate
    self.class.executed = true
    track_stat(:would_run)
  end
end

# Scenario 4: Rollback flow
class IntegrationRollback < Familia::Migration::Base
  self.migration_id = 'integration_rollback'

  class << self
    attr_accessor :state
  end
  self.state = :initial

  def migration_needed?; true; end

  def migrate
    self.class.state = :migrated
  end

  def down
    self.class.state = :rolled_back
  end
end

# Scenario 7: Error handling
class IntegrationFailingMigration < Familia::Migration::Base
  self.migration_id = 'integration_failing'

  def migration_needed?; true; end

  def migrate
    raise "Intentional failure for testing"
  end
end

# Scenario 8: Migration status reporting
class IntegrationStatusA < Familia::Migration::Base
  self.migration_id = 'integration_status_a'
  self.description = 'Status test A'

  def migration_needed?; true; end
  def migrate; end
end

class IntegrationStatusB < Familia::Migration::Base
  self.migration_id = 'integration_status_b'
  self.description = 'Status test B'

  def migration_needed?; true; end
  def migrate; end
  def down; end
end

# Scenario 9: for_realsies_this_time? guard
class IntegrationGuardedMigration < Familia::Migration::Base
  self.migration_id = 'integration_guarded'

  class << self
    attr_accessor :guarded_executed
  end
  self.guarded_executed = false

  def migration_needed?; true; end

  def migrate
    for_realsies_this_time? do
      self.class.guarded_executed = true
    end
    track_stat(:checked)
  end
end

# Scenario 10: Validate dependencies
class IntegrationOrphanMigration < Familia::Migration::Base
  self.migration_id = 'integration_orphan'
  self.dependencies = ['nonexistent_parent']

  def migration_needed?; true; end
  def migrate; end
end

# Scenario 11: Run with limit
class IntegrationLimitA < Familia::Migration::Base
  self.migration_id = 'integration_limit_a'
  self.dependencies = []
  def migration_needed?; true; end
  def migrate; end
end

class IntegrationLimitB < Familia::Migration::Base
  self.migration_id = 'integration_limit_b'
  self.dependencies = []
  def migration_needed?; true; end
  def migrate; end
end

class IntegrationLimitC < Familia::Migration::Base
  self.migration_id = 'integration_limit_c'
  self.dependencies = []
  def migration_needed?; true; end
  def migrate; end
end

# ============================================
# Scenario 1: Simple migration lifecycle
# ============================================

## Scenario 1: Migration runs and is recorded
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationSimpleMigration],
  registry: @registry
)
results = runner.run(dry_run: false)
[results.first[:status], @registry.applied?('integration_simple')]
#=> [:success, true]

## Scenario 1: Re-run skips already applied migration
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationSimpleMigration],
  registry: @registry
)
runner.pending.empty?
#=> true

reset_state
IntegrationSimpleMigration.ran_count = 0

# ============================================
# Scenario 2: Migration with dependencies
# ============================================

## Scenario 2: Dependencies run in correct order
IntegrationDepA.order = []
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationDepB, IntegrationDepA],
  registry: @registry
)
runner.run(dry_run: false)
IntegrationDepA.order
#=> [:a, :b]

## Scenario 2: Both are recorded as applied
[@registry.applied?('integration_dep_a'), @registry.applied?('integration_dep_b')]
#=> [true, true]

reset_state
IntegrationDepA.order = []

# ============================================
# Scenario 3: Dry run mode
# ============================================

## Scenario 3: Dry run does not persist
IntegrationDryRun.executed = false
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationDryRun],
  registry: @registry
)
@dry_run_results = runner.run(dry_run: true)
[@dry_run_results.first[:dry_run], @registry.applied?('integration_dry')]
#=> [true, false]

## Scenario 3: Dry run still returns success status
@dry_run_results.first[:status]
#=> :success

reset_state
IntegrationDryRun.executed = false

# ============================================
# Scenario 4: Rollback flow
# ============================================

## Scenario 4: Rollback executes down method
IntegrationRollback.state = :initial
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationRollback],
  registry: @registry
)
runner.run(dry_run: false)
runner.rollback('integration_rollback')
IntegrationRollback.state
#=> :rolled_back

## Scenario 4: Registry shows rollback
@registry.applied?('integration_rollback')
#=> false

## Scenario 4: Metadata shows rolled_back status
@rollback_meta = @registry.metadata('integration_rollback')
@rollback_meta[:status]
#=> 'rolled_back'

reset_state
IntegrationRollback.state = :initial

# ============================================
# Scenario 5: Lua script atomicity
# ============================================

## Scenario 5: rename_field is atomic
@test_key = "#{@prefix}:script_test"
@redis.hset(@test_key, 'old_field', 'test_value')
@redis.hset(@test_key, 'other_field', 'keep_me')

Familia::Migration::Script.execute(
  @redis,
  :rename_field,
  keys: [@test_key],
  argv: ['old_field', 'new_field']
)

[
  @redis.hexists(@test_key, 'old_field'),
  @redis.hget(@test_key, 'new_field'),
  @redis.hget(@test_key, 'other_field')
]
#=> [false, 'test_value', 'keep_me']

## Scenario 5: backup_and_modify_field creates backup
@backup_key = "#{@prefix}:backup_test"
@hash_key = "#{@prefix}:data_test"
@redis.hset(@hash_key, 'target', 'original')

Familia::Migration::Script.execute(
  @redis,
  :backup_and_modify_field,
  keys: [@hash_key, @backup_key],
  argv: ['target', 'modified', '3600']
)

[
  @redis.hget(@hash_key, 'target'),
  @redis.hget(@backup_key, "#{@hash_key}:target")
]
#=> ['modified', 'original']

reset_state

# ============================================
# Scenario 6: Configuration
# ============================================

## Scenario 6: Configuration defaults are set
config = Familia::Migration.config
[config.migrations_key, config.backup_ttl, config.batch_size]
#=> ['familia:migrations', 86400, 1000]

## Scenario 6: Configuration can be changed
Familia::Migration.configure do |c|
  c.batch_size = 500
end
Familia::Migration.config.batch_size
#=> 500

# Reset config
Familia::Migration.config.batch_size = 1000

# ============================================
# Scenario 7: Error handling
# ============================================

## Scenario 7: Failed migration returns error in result
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationFailingMigration],
  registry: @registry
)
@fail_result = runner.run(dry_run: false).first
[@fail_result[:status], @fail_result[:error].include?('Intentional failure')]
#=> [:failed, true]

## Scenario 7: Failed migration is not recorded as applied
@registry.applied?('integration_failing')
#=> false

reset_state

# ============================================
# Scenario 8: Migration status reporting
# ============================================

## Scenario 8: Status shows pending and applied correctly
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationStatusA, IntegrationStatusB],
  registry: @registry
)
runner.run_one(IntegrationStatusA, dry_run: false)
@status_list = runner.status
@statuses = @status_list.map { |s| [s[:migration_id], s[:status]] }.to_h
[@statuses['integration_status_a'], @statuses['integration_status_b']]
#=> [:applied, :pending]

## Scenario 8: Status correctly reports reversibility
@reversible_map = @status_list.map { |s| [s[:migration_id], s[:reversible]] }.to_h
[@reversible_map['integration_status_a'], @reversible_map['integration_status_b']]
#=> [false, true]

reset_state

# ============================================
# Scenario 9: for_realsies_this_time? guard
# ============================================

## Scenario 9: Guarded block skipped in dry run
IntegrationGuardedMigration.guarded_executed = false
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationGuardedMigration],
  registry: @registry
)
runner.run(dry_run: true)
IntegrationGuardedMigration.guarded_executed
#=> false

## Scenario 9: Guarded block executes in actual run
IntegrationGuardedMigration.guarded_executed = false
reset_state
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationGuardedMigration],
  registry: @registry
)
runner.run(dry_run: false)
IntegrationGuardedMigration.guarded_executed
#=> true

reset_state
IntegrationGuardedMigration.guarded_executed = false

# ============================================
# Scenario 10: Validate dependencies
# ============================================

## Scenario 10: Validate detects missing dependencies
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationOrphanMigration],
  registry: @registry
)
issues = runner.validate
issues.any? { |i| i[:type] == :missing_dependency && i[:dependency] == 'nonexistent_parent' }
#=> true

reset_state

# ============================================
# Scenario 11: Run with limit
# ============================================

## Scenario 11: Run with limit applies only N migrations
runner = Familia::Migration::Runner.new(
  migrations: [IntegrationLimitA, IntegrationLimitB, IntegrationLimitC],
  registry: @registry
)
@limit_results = runner.run(dry_run: false, limit: 2)
[@limit_results.size, runner.pending.size]
#=> [2, 1]

reset_state

# ============================================
# Teardown
# ============================================

reset_state
Familia::Migration.migrations.replace(@initial_migrations)
