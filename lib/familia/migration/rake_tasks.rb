# frozen_string_literal: true

require 'rake'
require_relative '../migration'

module Familia
  module Migration
    # RakeTasks provides a set of Rake tasks for managing Familia migrations.
    #
    # Tasks are installed automatically when this file is required. Available tasks:
    #
    #   familia:migrate         - Run all pending migrations
    #   familia:migrate:run     - Run all pending migrations
    #   familia:migrate:status  - Show migration status table
    #   familia:migrate:dry_run - Preview pending migrations (dry run)
    #   familia:migrate:rollback[ID] - Rollback a specific migration
    #   familia:migrate:validate - Validate migration dependencies
    #   familia:migrate:schema_drift - List models with schema drift
    #
    # @example Loading tasks in a Rakefile
    #   require 'familia/migration/rake_tasks'
    #
    # @example Loading tasks via .rake file
    #   load 'familia/migration/rake_tasks.rake'
    #
    class RakeTasks
      include Rake::DSL

      def initialize
        define_tasks
      end

      def define_tasks
        namespace :familia do
          namespace :migrate do
            desc 'Run all pending migrations'
            task :run do
              runner = Runner.new
              results = runner.run(dry_run: false)
              print_results(results)
            end

            desc 'Show migration status table'
            task :status do
              runner = Runner.new
              print_status(runner.status)
            end

            desc 'Preview pending migrations (dry run)'
            task :dry_run do
              runner = Runner.new
              results = runner.run(dry_run: true)
              print_results(results)
            end

            desc 'Rollback a specific migration'
            task :rollback, [:id] do |_t, args|
              abort 'Usage: rake familia:migrate:rollback[MIGRATION_ID]' unless args[:id]

              runner = Runner.new
              result = runner.rollback(args[:id])
              print_result(result)
            end

            desc 'Validate migration dependencies'
            task :validate do
              runner = Runner.new
              issues = runner.validate

              if issues.empty?
                puts 'All migrations valid'
              else
                puts "Found #{issues.size} issue(s):"
                issues.each do |issue|
                  puts "  - #{issue[:type]}: #{issue[:message] || issue[:dependency] || issue[:migration_id]}"
                end
                exit 1
              end
            end

            desc 'List models with schema drift'
            task :schema_drift do
              registry = Registry.new
              drift = registry.schema_drift

              if drift.empty?
                puts 'No schema drift detected'
              else
                puts 'Models with schema drift:'
                drift.each { |model| puts "  - #{model}" }
              end
            end
          end

          # Shortcut: familia:migrate runs all pending
          desc 'Run all pending migrations'
          task migrate: 'migrate:run'
        end
      end

      private

      def print_status(status_list)
        puts 'Migration Status:'
        puts '-' * 80

        applied_count = 0
        pending_count = 0

        status_list.each do |entry|
          if entry[:status] == :applied
            applied_count += 1
            time_str = entry[:applied_at]&.strftime('%Y-%m-%d %H:%M') || 'unknown'
            puts "  Applied    #{entry[:migration_id].ljust(45)} #{time_str}"
          else
            pending_count += 1
            puts "  Pending    #{entry[:migration_id]}"
          end
        end

        puts '-' * 80
        puts "Total: #{status_list.size} (#{applied_count} applied, #{pending_count} pending)"
      end

      def print_results(results)
        return puts 'No migrations to run' if results.empty?

        results.each do |result|
          status_indicator = case result[:status]
                             when :success then 'Applied'
                             when :skipped then 'Skipped'
                             when :failed then 'Failed'
                             when :rolled_back then 'Rolled back'
                             else 'Unknown'
                             end

          dry_run_note = result[:dry_run] ? ' (dry run)' : ''
          puts "#{status_indicator}: #{result[:migration_id]}#{dry_run_note}"

          if result[:error]
            puts "  Error: #{result[:error]}"
          end

          if result[:stats] && !result[:stats].empty?
            result[:stats].each do |key, value|
              puts "  #{key}: #{value}"
            end
          end
        end
      end

      def print_result(result)
        print_results([result])
      end
    end
  end
end

# Auto-install tasks when loaded
Familia::Migration::RakeTasks.new
