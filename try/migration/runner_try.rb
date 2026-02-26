# try/migration/runner_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

Familia.debug = false

@redis = Familia.dbclient
@prefix = "familia:test:runner:#{Process.pid}:#{Familia.now.to_i}"
@registry = Familia::Migration::Registry.new(redis: @redis, prefix: @prefix)

# Clean any existing test keys
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }

# Store initial migration count
@initial_migrations = Familia::Migration.migrations.dup

# Define test migration classes
class RunnerTestMigrationA < Familia::Migration::Base
  self.migration_id = 'runner_test_a'
  self.description = 'First migration'
  self.dependencies = []

  def migration_needed?
    true
  end

  def migrate
    track_stat(:a_ran)
  end
end

class RunnerTestMigrationB < Familia::Migration::Base
  self.migration_id = 'runner_test_b'
  self.description = 'Depends on A'
  self.dependencies = ['runner_test_a']

  def migration_needed?
    true
  end

  def migrate
    track_stat(:b_ran)
  end
end

class RunnerTestReversible < Familia::Migration::Base
  self.migration_id = 'runner_test_reversible'
  self.description = 'Reversible migration'
  self.dependencies = []

  def migration_needed?
    true
  end

  def migrate
    track_stat(:forward)
  end

  def down
    track_stat(:backward)
  end
end

@test_migrations = [RunnerTestMigrationA, RunnerTestMigrationB, RunnerTestReversible]

# Circular dependency test migrations
class CircularMigrationA < Familia::Migration::Base
  self.migration_id = 'circular_a'
  self.dependencies = ['circular_b']
  def migration_needed?; true; end
  def migrate; end
end

class CircularMigrationB < Familia::Migration::Base
  self.migration_id = 'circular_b'
  self.dependencies = ['circular_a']
  def migration_needed?; true; end
  def migrate; end
end

class CircularMigrationC < Familia::Migration::Base
  self.migration_id = 'circular_c'
  self.dependencies = ['circular_d']
  def migration_needed?; true; end
  def migrate; end
end

class CircularMigrationD < Familia::Migration::Base
  self.migration_id = 'circular_d'
  self.dependencies = ['circular_e']
  def migration_needed?; true; end
  def migrate; end
end

class CircularMigrationE < Familia::Migration::Base
  self.migration_id = 'circular_e'
  self.dependencies = ['circular_c']
  def migration_needed?; true; end
  def migrate; end
end

class SelfRefMigration < Familia::Migration::Base
  self.migration_id = 'self_ref'
  self.dependencies = ['self_ref']
  def migration_needed?; true; end
  def migrate; end
end

## Runner initializes with default values
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.is_a?(Familia::Migration::Runner)
#=> true

## status returns array of migration info
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
status = runner.status
status.is_a?(Array) && status.size == 3
#=> true

## status shows all as pending initially
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.status.all? { |s| s[:status] == :pending }
#=> true

## pending returns all migrations initially
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.pending.size
#=> 3

## validate returns empty array when dependencies valid
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.validate
#=> []

## validate detects missing dependencies
class MissingDepMigration < Familia::Migration::Base
  self.migration_id = 'missing_dep'
  self.dependencies = ['nonexistent']
  def migration_needed?; true; end
  def migrate; end
end
runner = Familia::Migration::Runner.new(
  migrations: [MissingDepMigration],
  registry: @registry
)
issues = runner.validate
issues.any? { |i| i[:type] == :missing_dependency }
#=> true

## run executes migrations respecting dependencies
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
results = runner.run(dry_run: false)
ids = results.map { |r| r[:migration_id] }
ids.index('runner_test_a') < ids.index('runner_test_b')
#=> true

## run records applied migrations
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
@registry.applied?('runner_test_a')
#=> true

## run_one with dry_run returns dry_run flag
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
result = runner.run_one(RunnerTestMigrationA, dry_run: true)
result[:dry_run]
#=> true

## dry run does not mark as applied
@registry.applied?('runner_test_a')
#=> false

## run with limit stops after N migrations
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
results = runner.run(dry_run: false, limit: 1)
results.size
#=> 1

## run_one executes single migration by class
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
result = runner.run_one(RunnerTestMigrationA, dry_run: false)
result[:status]
#=> :success

## run_one executes single migration by ID
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
result = runner.run_one('runner_test_reversible', dry_run: false)
result[:status]
#=> :success

## run_one raises DependencyNotMet if dependencies not applied
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
begin
  runner.run_one(RunnerTestMigrationB, dry_run: false)
  false
rescue Familia::Migration::Errors::DependencyNotMet
  true
end
#=> true

## rollback calls down method
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.run_one(RunnerTestReversible, dry_run: false)
result = runner.rollback('runner_test_reversible')
result[:status]
#=> :rolled_back

## rollback raises NotApplied if not applied
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
begin
  runner.rollback('runner_test_reversible')
  false
rescue Familia::Migration::Errors::NotApplied
  true
end
#=> true

## rollback raises HasDependents if others depend on it
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.run(dry_run: false)
begin
  runner.rollback('runner_test_a')
  false
rescue Familia::Migration::Errors::HasDependents
  true
end
#=> true

## rollback raises NotReversible if no down method
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
runner.run_one(RunnerTestMigrationA, dry_run: false)
begin
  runner.rollback('runner_test_a')
  false
rescue Familia::Migration::Errors::NotReversible
  true
end
#=> true

## NotFound raised for unknown migration ID
runner = Familia::Migration::Runner.new(migrations: @test_migrations, registry: @registry)
begin
  runner.run_one('nonexistent_migration', dry_run: false)
  false
rescue Familia::Migration::Errors::NotFound
  true
end
#=> true

## validate detects simple circular dependency (A -> B -> A)
runner = Familia::Migration::Runner.new(
  migrations: [CircularMigrationA, CircularMigrationB],
  registry: @registry
)
issues = runner.validate
issues.any? { |i| i[:type] == :circular_dependency }
#=> true

## validate detects complex circular dependency (C -> D -> E -> C)
runner = Familia::Migration::Runner.new(
  migrations: [CircularMigrationC, CircularMigrationD, CircularMigrationE],
  registry: @registry
)
issues = runner.validate
issues.any? { |i| i[:type] == :circular_dependency }
#=> true

## run raises CircularDependency for circular dependencies
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
runner = Familia::Migration::Runner.new(
  migrations: [CircularMigrationA, CircularMigrationB],
  registry: @registry
)
begin
  runner.run(dry_run: false)
  false
rescue Familia::Migration::Errors::CircularDependency
  true
end
#=> true

## Self-referencing dependency is detected
runner = Familia::Migration::Runner.new(
  migrations: [SelfRefMigration],
  registry: @registry
)
issues = runner.validate
issues.any? { |i| i[:type] == :circular_dependency }
#=> true

# Teardown
@redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
Familia::Migration.migrations.replace(@initial_migrations)
Familia::Migration.migrations.delete(MissingDepMigration)
Familia::Migration.migrations.delete(CircularMigrationA)
Familia::Migration.migrations.delete(CircularMigrationB)
Familia::Migration.migrations.delete(CircularMigrationC)
Familia::Migration.migrations.delete(CircularMigrationD)
Familia::Migration.migrations.delete(CircularMigrationE)
Familia::Migration.migrations.delete(SelfRefMigration)
