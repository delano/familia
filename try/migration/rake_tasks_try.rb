# frozen_string_literal: true

require 'rake'
require_relative '../../lib/familia/migration/rake_tasks'

# Enable metadata recording so descriptions are available
Rake::TaskManager.record_task_metadata = true

# Clear existing tasks and reload to ensure fresh state
Rake::Task.clear
Familia::Migration::RakeTasks.new

## All expected tasks are defined
expected_tasks = %w[
  familia:migrate
  familia:migrate:run
  familia:migrate:status
  familia:migrate:dry_run
  familia:migrate:rollback
  familia:migrate:validate
  familia:migrate:schema_drift
]
expected_tasks.all? { |name| Rake::Task.task_defined?(name) }
#=> true

## familia:migrate:run has correct description
Rake::Task['familia:migrate:run'].comment
#=> 'Run all pending migrations'

## familia:migrate:status has correct description
Rake::Task['familia:migrate:status'].comment
#=> 'Show migration status table'

## familia:migrate:dry_run has correct description
Rake::Task['familia:migrate:dry_run'].comment
#=> 'Preview pending migrations (dry run)'

## familia:migrate:rollback has correct description
Rake::Task['familia:migrate:rollback'].comment
#=> 'Rollback a specific migration'

## familia:migrate:validate has correct description
Rake::Task['familia:migrate:validate'].comment
#=> 'Validate migration dependencies'

## familia:migrate:schema_drift has correct description
Rake::Task['familia:migrate:schema_drift'].comment
#=> 'List models with schema drift'

## familia:migrate shortcut task has correct description
Rake::Task['familia:migrate'].comment
#=> 'Run all pending migrations'

## familia:migrate shortcut has familia:migrate:run as prerequisite
Rake::Task['familia:migrate'].prerequisites
#=> ['migrate:run']

## familia:migrate:rollback accepts an argument
task = Rake::Task['familia:migrate:rollback']
task.arg_names
#=> [:id]
