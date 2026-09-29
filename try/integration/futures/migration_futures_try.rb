# try/integration/futures/migration_futures_try.rb
#
# frozen_string_literal: true

# Migration entry points and the migration registry inside transaction and
# pipelined blocks. Running a migration needs replies, so the entry points
# raise Familia::OperationModeError there. Registry reads that only convert
# a reply pass the Future through; registry methods that decide from a
# reply raise. See docs/reference/transaction_safety.md for the policy.

require_relative '../../support/helpers/test_helpers'
require_relative '../../../lib/familia/migration'

Familia.debug = false

@prefix = "familia:test:futures_migration:#{Process.pid}"
@registry = Familia::Migration::Registry.new(prefix: @prefix)
@initial_migrations = Familia::Migration.migrations.dup

# Minimal migration that is always needed and records one stat.
class FuturesMigrationExample < Familia::Migration::Base
  self.migration_id = 'futures_migration_example'
  self.description = 'Futures migration example'

  def migration_needed?
    true
  end

  def migrate
    track_stat(:ran)
  end
end

@runner = Familia::Migration::Runner.new(migrations: [FuturesMigrationExample], registry: @registry)
@registry.record_applied(FuturesMigrationExample, {})

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## migration entry points inside a pipeline raise OperationModeError
[
  @refused.call { Familia.pipelined { FuturesMigrationExample.run(run: false) } },
  @refused.call { Familia.pipelined { FuturesMigrationExample.check_only } },
  @refused.call { Familia.pipelined { @runner.run(dry_run: true) } },
  @refused.call { Familia.pipelined { @runner.run_one(FuturesMigrationExample, dry_run: true) } },
  @refused.call { Familia.pipelined { @runner.status } },
  @refused.call { Familia.pipelined { @runner.pending } },
  @refused.call { Familia.transaction { @runner.rollback('futures_migration_example') } },
].uniq
#=> [Familia::OperationModeError]

## registry reads that convert a reply pass the Future through inside a pipeline
@ret = nil
Familia.pipelined do
  @ret = [@registry.applied?('futures_migration_example'), @registry.applied_at('futures_migration_example'),
          @registry.all_applied, @registry.metadata('futures_migration_example')]
end
[@ret.map(&:class).uniq, @ret.first.value.is_a?(Float), @ret.last.value.include?('"status":"applied"')]
#=> [[Redis::Future], true, true]

## registry methods that decide from a reply raise inside a transaction
[
  @refused.call { Familia.transaction { @registry.pending([FuturesMigrationExample]) } },
  @refused.call { Familia.transaction { @registry.status([FuturesMigrationExample]) } },
  @refused.call { Familia.transaction { @registry.record_rollback('futures_migration_example') } },
  @refused.call { Familia.transaction { @registry.schema_drift } },
  @refused.call { Familia.transaction { @registry.restore_backup('futures_migration_example') } },
].uniq
#=> [Familia::OperationModeError]

## a registry used inside a pipeline does not keep the pipeline connection afterwards
Familia.pipelined { @registry.applied?('futures_migration_example') }
[@registry.client.is_a?(Redis::PipelinedConnection), @registry.applied?('futures_migration_example')]
#=> [false, true]

## a registry without its own client issues all of a method's commands on one connection
# Without a connection provider, Familia.dbclient opens a new connection per
# call, so resolving the client per command would open one per restored field.
10.times { |i| @registry.backup_field('futures_migration_example', "#{@prefix}:restored", "f#{i}", "v#{i}") }
@stats_client = Familia.dbclient
@connections = -> { @stats_client.info('stats')['total_connections_received'].to_i }
@before = @connections.call
@restored = @registry.restore_backup('futures_migration_example')
[@restored, @connections.call - @before <= 1, Familia.dbclient.hget("#{@prefix}:restored", 'f9')]
#=> [10, true, "v9"]

## a registry built with its own client still answers inside a pipeline
@own_client_registry = Familia::Migration::Registry.new(redis: Familia.dbclient, prefix: @prefix)
@ret = nil
Familia.pipelined { @ret = @own_client_registry.pending([FuturesMigrationExample]) }
@ret
#=> []

## outside a block: the registry and runner keep their return types
[@registry.applied?('futures_migration_example'), @registry.applied_at('futures_migration_example').class,
 @registry.metadata('futures_migration_example')[:status], @runner.status.first[:status], @runner.pending]
#=> [true, Time, "applied", :applied, []]

# Teardown
Familia.dbclient.scan_each(match: "#{@prefix}*").each { |key| Familia.dbclient.del(key) }
Familia::Migration.migrations.replace(@initial_migrations)
