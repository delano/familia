# lib/familia/migration/base.rb
#
# frozen_string_literal: true

module Familia
  module Migration
    # Base class for Familia data migrations providing common infrastructure
    # for idempotent data transformations and configuration updates.
    #
    # Unlike traditional database migrations, these migrations:
    # - Don't track execution state in a migrations table
    # - Use {#migration_needed?} to detect if changes are required
    # - Support both dry-run and actual execution modes
    # - Provide built-in statistics tracking and logging
    #
    # ## Subclassing Requirements
    #
    # Subclasses must implement these methods:
    # - {#migration_needed?} - Detect if migration should run
    # - {#migrate} - Perform the actual migration work
    #
    # Subclasses may override:
    # - {#prepare} - Initialize and validate migration parameters
    # - {#down} - Rollback logic for reversible migrations
    #
    # ## Usage Patterns
    #
    # For simple data migrations, extend Base directly:
    #
    #   class ConfigurationMigration < Familia::Migration::Base
    #     self.migration_id = '20260131_120000_config_update'
    #
    #     def migration_needed?
    #       !redis.exists('config:new_feature_flag')
    #     end
    #
    #     def migrate
    #       for_realsies_this_time? do
    #         redis.set('config:new_feature_flag', 'true')
    #       end
    #       track_stat(:settings_updated)
    #     end
    #   end
    #
    # For record-by-record processing, use {Model}.
    # For bulk updates with Redis pipelining, use {Pipeline}.
    #
    # ## CLI Usage
    #
    #   ConfigurationMigration.cli_run              # Dry run (preview)
    #   ConfigurationMigration.cli_run(['--run'])   # Actual execution
    #
    # @abstract Subclass and implement {#migration_needed?} and {#migrate}
    # @see Model For individual record processing
    # @see Pipeline For bulk record processing with pipelining
    class Base
      class << self
        # Unique identifier for this migration
        # @return [String] format: {timestamp}_{snake_case_name}
        attr_accessor :migration_id

        # Human-readable description of what this migration does
        # @return [String]
        attr_accessor :description

        # List of migration IDs that must run before this one
        # @return [Array<String>]
        attr_accessor :dependencies

        # Auto-registration hook called when a subclass is defined.
        # Registers the migration with Familia::Migration.migrations.
        #
        # @param subclass [Class] The inheriting class
        def inherited(subclass)
          super
          subclass.dependencies ||= []

          # Only register named classes (skip anonymous classes)
          # Use respond_to? to handle load-order edge cases where migrations
          # array may not yet be defined (e.g., Model class loading during require)
          return if subclass.name.nil?
          return unless Familia::Migration.respond_to?(:migrations)

          Familia::Migration.migrations << subclass
        end

        # CLI entry point for migration execution
        #
        # Handles command-line argument parsing and returns appropriate exit codes.
        # This is the recommended entry point for migration scripts.
        #
        # @param argv [Array<String>] command-line arguments (default: ARGV)
        # @return [Integer] exit code (0 = success, 1 = error/action required)
        #
        # @example In migration script
        #   if __FILE__ == $0
        #     exit(MyMigration.cli_run)
        #   end
        def cli_run(argv = ARGV)
          if argv.include?('--check')
            check_only
          else
            result = run(run: argv.include?('--run'))
            # nil (not needed) and true (success) both return 0
            # only false (failure) returns 1
            result == false ? 1 : 0
          end
        end

        # Check-only mode for programmatic use
        #
        # Returns exit code indicating whether migration is needed.
        # Does not perform any migration work.
        #
        # @return [Integer] 0 if no migration needed, 1 if migration needed
        def check_only
          migration = new
          migration.prepare
          migration.migration_needed? ? 1 : 0
        end

        # Main entry point for migration execution
        #
        # Orchestrates the full migration process including preparation,
        # conditional execution based on {#migration_needed?}, and cleanup.
        #
        # @param options [Hash] CLI options, typically { run: true/false }
        # @return [Boolean, nil] true if migration completed successfully,
        #   nil if not needed, false if failed
        def run(options = {})
          migration         = new
          migration.options = options
          migration.prepare

          return migration.handle_migration_not_needed unless migration.migration_needed?

          migration.migrate
        end
      end

      # CLI options passed to migration, typically { run: true/false }
      # @return [Hash] the options hash
      attr_accessor :options

      # Migration statistics for tracking operations performed
      # @return [Hash] auto-incrementing counters for named statistics
      attr_reader :stats

      # Initialize new migration instance with default state
      def initialize(options = {})
        @options = options
        @stats   = Hash.new(0)  # Auto-incrementing counter for tracking migration stats
      end

      # Hook for subclass initialization and validation
      #
      # Override this method to:
      # - Set instance variables needed by the migration
      # - Validate prerequisites and configuration
      # - Initialize connections or external dependencies
      #
      # @return [void]
      def prepare
        debug('Preparing migration - default implementation')
      end

      # Perform actual migration work
      #
      # This is the core migration logic that subclasses must implement.
      # Use {#for_realsies_this_time?} to wrap actual changes and
      # {#track_stat} to record operations performed.
      #
      # @abstract Subclasses must implement this method
      # @return [Boolean] true if migration succeeded
      # @raise [NotImplementedError] if not implemented by subclass
      def migrate
        raise NotImplementedError, "#{self.class} must implement #migrate"
      end

      # Detect if migration needs to run
      #
      # This method should implement idempotency logic by checking
      # current system state and returning false if migration has
      # already been applied or is not needed.
      #
      # @abstract Subclasses must implement this method
      # @return [Boolean] true if migration should proceed
      # @raise [NotImplementedError] if not implemented by subclass
      def migration_needed?
        raise NotImplementedError, "#{self.class} must implement #migration_needed?"
      end

      # Optional rollback logic.
      # Override in subclass to support reversible migrations.
      def down
        # Override in subclass for rollback support
      end

      # Check if this migration has rollback support.
      #
      # @return [Boolean] true if down method is overridden
      def reversible?
        method(:down).owner != Familia::Migration::Base
      end

      # === Run Mode Control ===

      # Check if migration is running in dry-run mode
      # @return [Boolean] true if no changes should be made
      def dry_run?
        !options[:run]
      end

      # Check if migration is running in actual execution mode
      # @return [Boolean] true if changes will be applied
      def actual_run?
        options[:run]
      end

      # Display run mode banner with appropriate warnings
      # @return [void]
      def run_mode_banner
        header("Running in #{dry_run? ? 'DRY RUN' : 'ACTUAL RUN'} mode")
        info(dry_run? ? 'No changes will be made' : 'Changes WILL be applied to the database')
        info(separator)
      end

      # Execute block only in actual run mode
      #
      # Use this to wrap code that makes actual changes to the system.
      # In dry-run mode, the block will not be executed.
      #
      # @yield Block to execute if in actual run mode
      # @return [Boolean] true if block was executed, false if skipped
      def for_realsies_this_time?
        return false unless actual_run?

        yield if block_given?
        true
      end

      # Execute block only in dry run mode
      #
      # Use this for dry-run specific logging or validation.
      #
      # @yield Block to execute if in dry run mode
      # @return [Boolean] true if block was executed, false if skipped
      def dry_run_only?
        return false unless dry_run?

        yield if block_given?
        true
      end

      # === Statistics Tracking ===

      # Increment named counter for migration statistics
      #
      # Use this to track operations, errors, skipped records, etc.
      # Statistics are automatically displayed in migration summaries.
      #
      # @param key [Symbol] stat name to increment
      # @param increment [Integer] amount to add (default 1)
      # @return [nil]
      def track_stat(key, increment = 1)
        @stats[key] += increment
        nil
      end

      # === Logging Interface ===

      # Print formatted header with separator lines
      # @param message [String] header text to display
      # @return [void]
      def header(message)
        info ''
        info separator
        info(message.upcase)
      end

      # Log informational message
      # @param message [String] message to log
      # @return [void]
      def info(message = nil)
        Familia.logger.info { message } if message
      end

      # Log debug message
      # @param message [String] message to log
      # @return [void]
      def debug(message = nil)
        Familia.logger.debug { message } if message
      end

      # Log warning message
      # @param message [String] message to log
      # @return [void]
      def warn(message = nil)
        Familia.logger.warn { message } if message
      end

      # Log error message
      # @param message [String] message to log
      # @return [void]
      def error(message = nil)
        Familia.logger.error { message } if message
      end

      # Generate separator line for visual formatting
      # @return [String] dash separator line
      def separator
        '-' * 60
      end

      # Progress indicator for long operations
      #
      # Displays progress updates at specified intervals to avoid
      # overwhelming the log output during bulk operations.
      #
      # @param current [Integer] current item number
      # @param total [Integer] total items to process
      # @param message [String] operation description
      # @param step [Integer] progress reporting frequency (default 100)
      # @return [void]
      def progress(current, total, message = 'Processing', step = 100)
        return unless current % step == 0 || current == total

        info "#{message} #{current}/#{total}..."
      end

      # Display migration summary with custom content block
      #
      # Automatically adjusts header based on run mode and yields
      # the current mode to the block for conditional content.
      #
      # @param title [String, nil] custom summary title
      # @yield [Symbol] :dry_run or :actual_run for conditional content
      # @return [void]
      def print_summary(title = nil)
        if dry_run?
          header(title || 'DRY RUN SUMMARY')
          yield(:dry_run) if block_given?
        else
          header(title || 'ACTUAL RUN SUMMARY')
          yield(:actual_run) if block_given?
        end
      end

      # Handle case where migration is not needed
      #
      # Called automatically when {#migration_needed?} returns false.
      # Provides standard messaging about migration state.
      #
      # @return [nil]
      def handle_migration_not_needed
        info('')
        info('Migration needed? false.')
        info('')
        info('This usually means that the migration has already been applied.')
        nil
      end

      # === Schema Validation ===

      # Validate an object against its schema
      #
      # Uses the SchemaRegistry to validate an object's data against
      # its registered JSON schema. Returns validation results without
      # raising exceptions.
      #
      # @param obj [Object] object with to_h method
      # @param context [String, nil] context for error messages (e.g., 'before transform')
      # @return [Hash] { valid: Boolean, errors: Array }
      def validate_schema(obj, context: nil)
        return { valid: true, errors: [] } unless schema_validation_enabled?

        klass_name = obj.class.name
        data = obj.respond_to?(:to_h) ? obj.to_h : obj

        result = Familia::SchemaRegistry.validate(klass_name, data)

        unless result[:valid]
          context_msg = context ? " (#{context})" : ''
          warn "Schema validation failed for #{klass_name}#{context_msg}: #{result[:errors].size} error(s)"
          result[:errors].first(3).each do |e|
            debug "  - #{e['type'] || 'error'}: #{e['data_pointer'] || '/'}"
          end
        end

        result
      end

      # Validate an object or raise SchemaValidationError
      #
      # Uses the SchemaRegistry to validate an object's data against
      # its registered JSON schema. Raises an exception if validation fails.
      #
      # @param obj [Object] object with to_h method
      # @param context [String, nil] context for error messages
      # @return [true] if valid
      # @raise [Familia::SchemaValidationError] if validation fails
      def validate_schema!(obj, context: nil)
        result = validate_schema(obj, context: context)
        unless result[:valid]
          raise Familia::SchemaValidationError.new(result[:errors])
        end

        true
      end

      # Check if schema validation is enabled for this migration
      #
      # Schema validation is enabled by default when SchemaRegistry is loaded.
      # Use {#skip_schema_validation!} to disable for this migration instance.
      #
      # @return [Boolean]
      def schema_validation_enabled?
        @schema_validation != false && Familia::SchemaRegistry.loaded?
      end

      # Disable schema validation for this migration
      #
      # Call this in {#prepare} or at any point before validation to
      # skip all schema validation for this migration run.
      #
      # @return [void]
      def skip_schema_validation!
        @schema_validation = false
      end

      protected

      # Access to database client
      #
      # Provides a database connection for migrations
      # that need to access data outside of Familia models.
      #
      # @return [Redis] configured Redis connection
      def dbclient
        @dbclient ||= Familia.dbclient
      end

      # Alias for dbclient for convenience
      alias redis dbclient
    end
  end
end
