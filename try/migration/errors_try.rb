# try/migration/errors_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration/errors'

## MigrationError inherits from StandardError
Familia::Migration::Errors::MigrationError.superclass
#=> StandardError

## NotReversible inherits from MigrationError
Familia::Migration::Errors::NotReversible.superclass
#=> Familia::Migration::Errors::MigrationError

## NotApplied inherits from MigrationError
Familia::Migration::Errors::NotApplied.superclass
#=> Familia::Migration::Errors::MigrationError

## NotFound inherits from MigrationError
Familia::Migration::Errors::NotFound.superclass
#=> Familia::Migration::Errors::MigrationError

## DependencyNotMet inherits from MigrationError
Familia::Migration::Errors::DependencyNotMet.superclass
#=> Familia::Migration::Errors::MigrationError

## HasDependents inherits from MigrationError
Familia::Migration::Errors::HasDependents.superclass
#=> Familia::Migration::Errors::MigrationError

## CircularDependency inherits from MigrationError
Familia::Migration::Errors::CircularDependency.superclass
#=> Familia::Migration::Errors::MigrationError

## PreconditionFailed inherits from MigrationError
Familia::Migration::Errors::PreconditionFailed.superclass
#=> Familia::Migration::Errors::MigrationError

## All error classes are defined as constants
[
  :MigrationError,
  :NotReversible,
  :NotApplied,
  :NotFound,
  :DependencyNotMet,
  :HasDependents,
  :CircularDependency,
  :PreconditionFailed
].all? { |name| Familia::Migration::Errors.const_defined?(name) }
#=> true

## Errors can be raised with custom messages
begin
  raise Familia::Migration::Errors::NotFound, "Migration xyz not found"
rescue Familia::Migration::Errors::MigrationError => e
  e.message
end
#=> "Migration xyz not found"

## Errors can be rescued by parent class
begin
  raise Familia::Migration::Errors::CircularDependency, "A depends on B depends on A"
rescue Familia::Migration::Errors::MigrationError => e
  e.class.name.split('::').last
end
#=> "CircularDependency"
