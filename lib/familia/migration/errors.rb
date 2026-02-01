# frozen_string_literal: true

module Familia
  module Migration
    module Errors
      # Base class for all migration errors
      class MigrationError < StandardError; end

      # Raised when attempting to rollback a migration without a down method
      class NotReversible < MigrationError; end

      # Raised when attempting to rollback a migration that hasn't been applied
      class NotApplied < MigrationError; end

      # Raised when a migration ID cannot be found
      class NotFound < MigrationError; end

      # Raised when a migration's dependencies haven't been applied
      class DependencyNotMet < MigrationError; end

      # Raised when attempting to rollback a migration that other migrations depend on
      class HasDependents < MigrationError; end

      # Raised when migration dependencies form a cycle
      class CircularDependency < MigrationError; end

      # Raised when migration preconditions are not met
      class PreconditionFailed < MigrationError; end
    end
  end
end
