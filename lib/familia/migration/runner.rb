# frozen_string_literal: true

module Familia
  module Migration
    # Runner orchestrates migration execution with dependency resolution.
    #
    # Provides methods for querying migration status, validating dependencies,
    # and executing migrations in the correct order using topological sorting.
    #
    # @example Basic usage
    #   runner = Familia::Migration::Runner.new
    #   runner.status        # => Array of migration status hashes
    #   runner.pending       # => Array of unapplied migration classes
    #   runner.run           # => Execute all pending migrations
    #
    # @example Dry run
    #   runner.run(dry_run: true)  # Preview without applying changes
    #
    # @example Rolling back
    #   runner.rollback('20260131_add_status_field')
    #
    class Runner
      # @return [Array<Class>] Migration classes to operate on
      attr_reader :migrations

      # @return [Registry] Registry for tracking applied migrations
      attr_reader :registry

      # @return [Logger] Logger for migration output
      attr_reader :logger

      # Initialize a new Runner instance.
      #
      # @param migrations [Array<Class>, nil] Migration classes (defaults to registered migrations)
      # @param registry [Registry, nil] Registry instance (defaults to new Registry)
      # @param logger [Logger, nil] Logger instance (defaults to Familia.logger)
      #
      def initialize(migrations: nil, registry: nil, logger: nil)
        @migrations = migrations || Familia::Migration.migrations
        @registry = registry || Registry.new
        @logger = logger || Familia.logger
      end

      # --- Status Methods ---

      # Get the status of all migrations.
      #
      # @return [Array<Hash>] Array of migration info hashes with keys:
      #   - :migration_id [String] The migration identifier
      #   - :description [String] Human-readable description
      #   - :status [Symbol] :applied or :pending
      #   - :applied_at [Time, nil] When the migration was applied
      #   - :reversible [Boolean] Whether the migration has a down method
      #
      def status
        @migrations.map do |klass|
          id = klass.migration_id
          applied = @registry.applied?(id)
          {
            migration_id: id,
            description: klass.description,
            status: applied ? :applied : :pending,
            applied_at: applied ? @registry.applied_at(id) : nil,
            reversible: klass.new.reversible?,
          }
        end
      end

      # Get all pending (unapplied) migrations.
      #
      # @return [Array<Class>] Migration classes that haven't been applied
      #
      def pending
        @registry.pending(@migrations)
      end

      # Validate migration dependencies and configuration.
      #
      # @return [Array<Hash>] Array of issue hashes with keys:
      #   - :type [Symbol] Type of issue (:missing_dependency, :circular_dependency)
      #   - :migration_id [String] Migration with the issue (for missing deps)
      #   - :dependency [String] Missing dependency ID (for missing deps)
      #   - :message [String] Error message (for circular deps)
      #
      def validate
        issues = []

        # Check for missing dependencies
        all_ids = @migrations.map(&:migration_id)
        @migrations.each do |klass|
          (klass.dependencies || []).each do |dep_id|
            unless all_ids.include?(dep_id)
              issues << {
                type: :missing_dependency,
                migration_id: klass.migration_id,
                dependency: dep_id,
              }
            end
          end
        end

        # Check for circular dependencies
        begin
          topological_sort(@migrations)
        rescue Familia::Migration::Errors::CircularDependency => e
          issues << { type: :circular_dependency, message: e.message }
        end

        issues
      end

      # --- Execution Methods ---

      # Run all pending migrations in dependency order.
      #
      # @param dry_run [Boolean] If true, preview without applying changes
      # @param limit [Integer, nil] Maximum number of migrations to run
      # @return [Array<Hash>] Results for each migration attempted
      #
      def run(dry_run: false, limit: nil)
        pending_migrations = topological_sort(pending)
        pending_migrations = pending_migrations.first(limit) if limit

        results = []
        pending_migrations.each do |klass|
          result = run_one(klass, dry_run: dry_run)
          results << result
          break if result[:status] == :failed
        end
        results
      end

      # Run a single migration.
      #
      # @param migration_class_or_id [Class, String] Migration class or ID
      # @param dry_run [Boolean] If true, preview without applying changes
      # @return [Hash] Result hash with keys:
      #   - :migration_id [String] The migration identifier
      #   - :dry_run [Boolean] Whether this was a dry run
      #   - :status [Symbol] :success, :skipped, or :failed
      #   - :stats [Hash] Statistics from the migration
      #   - :error [String] Error message (if failed)
      #
      def run_one(migration_class_or_id, dry_run: false)
        klass = resolve_migration(migration_class_or_id)

        # Validate dependencies are applied
        (klass.dependencies || []).each do |dep_id|
          unless @registry.applied?(dep_id)
            raise Familia::Migration::Errors::DependencyNotMet,
                  "Dependency #{dep_id} not applied for #{klass.migration_id}"
          end
        end

        instance = klass.new(run: !dry_run)
        instance.prepare

        result = {
          migration_id: klass.migration_id,
          dry_run: dry_run,
          stats: {},
        }

        begin
          if instance.migration_needed?
            instance.migrate
            result[:status] = :success
            result[:stats] = instance.stats
            @registry.record_applied(instance, instance.stats) unless dry_run
          else
            result[:status] = :skipped
          end
        rescue StandardError => e
          result[:status] = :failed
          result[:error] = e.message
          @logger.error { "Migration failed: #{e.message}" }
        end

        result
      end

      # Rollback a previously applied migration.
      #
      # @param migration_id [String] The migration identifier to rollback
      # @return [Hash] Result hash with keys:
      #   - :migration_id [String] The migration identifier
      #   - :status [Symbol] :rolled_back or :failed
      #   - :error [String] Error message (if failed)
      # @raise [Errors::NotApplied] if migration hasn't been applied
      # @raise [Errors::HasDependents] if other migrations depend on this one
      # @raise [Errors::NotReversible] if migration has no down method
      #
      def rollback(migration_id)
        klass = resolve_migration(migration_id)

        unless @registry.applied?(migration_id)
          raise Familia::Migration::Errors::NotApplied,
                "Migration #{migration_id} is not applied"
        end

        # Check no dependents are applied
        @migrations.each do |m|
          if (m.dependencies || []).include?(migration_id) && @registry.applied?(m.migration_id)
            raise Familia::Migration::Errors::HasDependents,
                  "Cannot rollback: #{m.migration_id} depends on #{migration_id}"
          end
        end

        instance = klass.new

        unless instance.reversible?
          raise Familia::Migration::Errors::NotReversible,
                "Migration #{migration_id} does not have a down method"
        end

        result = { migration_id: migration_id }

        begin
          instance.down
          @registry.record_rollback(migration_id)
          result[:status] = :rolled_back
        rescue StandardError => e
          result[:status] = :failed
          result[:error] = e.message
        end

        result
      end

      private

      # Sort migrations in dependency order using Kahn's algorithm.
      #
      # @param migrations [Array<Class>] Migrations to sort
      # @return [Array<Class>] Migrations in execution order
      # @raise [Errors::CircularDependency] if a cycle is detected
      #
      def topological_sort(migrations)
        return [] if migrations.empty?

        # Build graph
        id_to_class = migrations.each_with_object({}) { |m, h| h[m.migration_id] = m }
        in_degree = Hash.new(0)
        graph = Hash.new { |h, k| h[k] = [] }

        migrations.each do |klass|
          id = klass.migration_id
          (klass.dependencies || []).each do |dep_id|
            # Only consider dependencies that are in our migration set
            next unless id_to_class.key?(dep_id)

            graph[dep_id] << id
            in_degree[id] += 1
          end
          in_degree[id] ||= 0 # Ensure entry exists
        end

        # Find nodes with no dependencies
        queue = migrations.select { |m| in_degree[m.migration_id].zero? }
                          .map(&:migration_id)
        result = []

        until queue.empty?
          id = queue.shift
          result << id_to_class[id]

          graph[id].each do |dependent_id|
            in_degree[dependent_id] -= 1
            queue << dependent_id if in_degree[dependent_id].zero?
          end
        end

        if result.size != migrations.size
          raise Familia::Migration::Errors::CircularDependency,
                'Circular dependency detected in migrations'
        end

        result
      end

      # Resolve a migration class from a class or ID string.
      #
      # @param class_or_id [Class, String] Migration class or ID
      # @return [Class] The migration class
      # @raise [Errors::NotFound] if migration ID not found
      # @raise [ArgumentError] if invalid argument type
      #
      def resolve_migration(class_or_id)
        case class_or_id
        when Class
          class_or_id
        when String
          klass = @migrations.find { |m| m.migration_id == class_or_id }
          raise Familia::Migration::Errors::NotFound, "Migration #{class_or_id} not found" unless klass

          klass
        else
          raise ArgumentError, "Expected Class or String, got #{class_or_id.class}"
        end
      end
    end
  end
end
