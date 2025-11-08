# try/features/relationships/participation_unresolved_target_try.rb
#
# frozen_string_literal: true

# Test for proper error handling when target class cannot be resolved
#
# This test verifies that participates_in raises a helpful error when
# the target class hasn't been loaded yet or doesn't exist.

require_relative '../../support/helpers/test_helpers'

## Test error message when target class doesn't exist (Symbol)
begin
  class UnresolvedTargetTest1 < Familia::Horreum
    feature :relationships
    identifier_field :id
    field :id

    participates_in :NonExistentTargetClass, :items
  end
  @error_raised = false
rescue ArgumentError => e
  @error_raised = true
  @error_message = e.message
end
@error_raised
#=> true

## Test error message includes the unresolved class name
@error_message.include?('NonExistentTargetClass')
#=> true

## Test error message mentions load order issue
@error_message.include?('load order')
#=> true

## Test error message mentions Familia.members
@error_message.include?('Familia.members')
#=> true

## Test error message includes list of registered classes
@error_message.include?('Current registered classes')
#=> true

## Test error when target class doesn't exist (String)
begin
  class UnresolvedTargetTest2 < Familia::Horreum
    feature :relationships
    identifier_field :id
    field :id

    participates_in 'AnotherNonExistentClass', :items
  end
  @string_error_raised = false
rescue ArgumentError => e
  @string_error_raised = true
  @string_error_message = e.message
end
@string_error_raised
#=> true

## Test error message for String target includes class name
@string_error_message.include?('AnotherNonExistentClass')
#=> true

## Test error provides solution hint
@string_error_message.include?('Solution')
#=> true

## Test that Class objects don't trigger the error (they're already resolved)
# This should work fine - no error expected
class ExistingTargetClass < Familia::Horreum
  feature :relationships
  identifier_field :id
  field :id
end

class WorkingParticipant < Familia::Horreum
  feature :relationships
  identifier_field :id
  field :id

  # This should work - ExistingTargetClass is already defined
  participates_in ExistingTargetClass, :items
end

# Verify the class was created successfully
WorkingParticipant.ancestors.include?(Familia::Horreum)
#=> true

## Test that resolved Symbol target works (no error)
class PreDefinedTarget < Familia::Horreum
  feature :relationships
  identifier_field :id
  field :id
end

class SymbolParticipant < Familia::Horreum
  feature :relationships
  identifier_field :id
  field :id

  # This should work - PreDefinedTarget is defined above
  participates_in :PreDefinedTarget, :items
end

# Verify it worked
SymbolParticipant.ancestors.include?(Familia::Horreum)
#=> true
