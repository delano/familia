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

## actual_run? returns false by default
TestBaseMigration.new.actual_run?
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

## redis accessor returns connection
instance = TestBaseMigration.new
instance.redis.respond_to?(:get)
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

# Cleanup - remove test migrations from registry
Familia::Migration.migrations.delete(TestBaseMigration)
Familia::Migration.migrations.delete(ReversibleTestMigration)
