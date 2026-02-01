# try/migration/base_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

Familia.debug = false

# Store initial migration count to detect auto-registration
@initial_count = Familia::Migration.migrations.size

# Define test migrations inline
class TestBaseMigration < Familia::Migration::Base
  self.migration_id = 'test_20260131_base'
  self.description = 'Test base migration'
  self.dependencies = ['some_other_migration']

  def migration_needed?
    true
  end

  def migrate
    track_stat(:items_processed, 5)
  end
end

class ReversibleTestMigration < Familia::Migration::Base
  self.migration_id = 'test_20260131_reversible'

  def migration_needed?
    true
  end

  def migrate
    # do something
  end

  def down
    # undo something
  end
end

class CliTestMigration < Familia::Migration::Base
  self.migration_id = 'cli_test_migration'

  class << self
    attr_accessor :migration_needed_value, :migrate_called
  end
  self.migration_needed_value = true
  self.migrate_called = false

  def migration_needed?
    self.class.migration_needed_value
  end

  def migrate
    self.class.migrate_called = true
    true
  end
end

## migration_id class attribute works
TestBaseMigration.migration_id
#=> 'test_20260131_base'

## description class attribute works
TestBaseMigration.description
#=> 'Test base migration'

## dependencies class attribute works
TestBaseMigration.dependencies
#=> ['some_other_migration']

## Subclassing auto-registers migration
Familia::Migration.migrations.size > @initial_count
#=> true

## Subclass is in migrations list
Familia::Migration.migrations.include?(TestBaseMigration)
#=> true

## reversible? returns false when down not overridden
TestBaseMigration.new.reversible?
#=> false

## reversible? returns true when down is overridden
ReversibleTestMigration.new.reversible?
#=> true

## dry_run? returns true by default (no :run option)
TestBaseMigration.new.dry_run?
#=> true

## actual_run? returns falsy by default
TestBaseMigration.new.actual_run? ? true : false
#=> false

## dry_run? returns false when run: true
TestBaseMigration.new(run: true).dry_run?
#=> false

## actual_run? returns true when run: true
TestBaseMigration.new(run: true).actual_run?
#=> true

## for_realsies_this_time? yields only in actual run
results = []
dry = TestBaseMigration.new(run: false)
dry.for_realsies_this_time? { results << :dry }
live = TestBaseMigration.new(run: true)
live.for_realsies_this_time? { results << :live }
results
#=> [:live]

## track_stat increments counter
instance = TestBaseMigration.new
instance.track_stat(:foo)
instance.track_stat(:foo)
instance.track_stat(:bar, 5)
[instance.stats[:foo], instance.stats[:bar]]
#=> [2, 5]

## stats hash defaults to 0
instance = TestBaseMigration.new
instance.stats[:nonexistent]
#=> 0

## redis accessor returns connection (via send for protected method)
instance = TestBaseMigration.new
instance.send(:redis).respond_to?(:get)
#=> true

## Base class migration_needed? raises NotImplementedError
begin
  Familia::Migration::Base.new.migration_needed?
  false
rescue NotImplementedError
  true
end
#=> true

## Base class migrate raises NotImplementedError
begin
  Familia::Migration::Base.new.migrate
  false
rescue NotImplementedError
  true
end
#=> true

## prepare can be called without error
instance = TestBaseMigration.new
instance.prepare
true
#=> true

## Logging methods exist
instance = TestBaseMigration.new
[:info, :debug, :warn, :error, :header, :progress].all? { |m| instance.respond_to?(m) }
#=> true

## cli_run returns 0 for dry run success
CliTestMigration.migrate_called = false
CliTestMigration.migration_needed_value = true
result = CliTestMigration.cli_run([])
[result, CliTestMigration.migrate_called]
#=> [0, true]

## cli_run returns 0 for actual run success
CliTestMigration.migrate_called = false
CliTestMigration.migration_needed_value = true
result = CliTestMigration.cli_run(['--run'])
[result, CliTestMigration.migrate_called]
#=> [0, true]

## cli_run with --check returns 1 when migration needed
CliTestMigration.migration_needed_value = true
result = CliTestMigration.cli_run(['--check'])
result
#=> 1

## cli_run with --check returns 0 when migration not needed
CliTestMigration.migration_needed_value = false
result = CliTestMigration.cli_run(['--check'])
result
#=> 0

## cli_run returns 0 when migration not needed
CliTestMigration.migration_needed_value = false
CliTestMigration.migrate_called = false
result = CliTestMigration.cli_run([])
[result, CliTestMigration.migrate_called]
#=> [0, false]

## check_only returns 1 when migration needed
CliTestMigration.migration_needed_value = true
CliTestMigration.check_only
#=> 1

## check_only returns 0 when migration not needed
CliTestMigration.migration_needed_value = false
CliTestMigration.check_only
#=> 0

## dry_run_only? yields only in dry run mode
results = []
dry = TestBaseMigration.new(run: false)
dry.dry_run_only? { results << :dry }
live = TestBaseMigration.new(run: true)
live.dry_run_only? { results << :live }
results
#=> [:dry]

## dry_run_only? returns true in dry run mode
TestBaseMigration.new(run: false).dry_run_only?
#=> true

## dry_run_only? returns false in actual run mode
TestBaseMigration.new(run: true).dry_run_only?
#=> false

# Cleanup - remove test migrations from registry
Familia::Migration.migrations.delete(TestBaseMigration)
Familia::Migration.migrations.delete(ReversibleTestMigration)
Familia::Migration.migrations.delete(CliTestMigration)
