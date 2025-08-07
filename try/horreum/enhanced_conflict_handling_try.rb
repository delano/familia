# try/horreum/enhanced_conflict_handling_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

## Valid strategies are defined correctly
Familia::VALID_STRATEGIES.include?(:raise)
#=> true

## Valid strategies include all expected options
Familia::VALID_STRATEGIES
#=> [:raise, :skip, :warn, :overwrite]

## Overwrite strategy removes existing method and defines new one
class OverwriteStrategyTest < Familia::Horreum
  identifier_field :id
  field :id

  def conflicting_method
    "original_method"
  end

  field :conflicting_method, on_conflict: :overwrite
end
@overwrite_test = OverwriteStrategyTest.new(id: 'overwrite1')
@overwrite_test.conflicting_method = "new_value"
@overwrite_test.conflicting_method
#=> "new_value"

## Overwrite strategy works with fast methods too
@overwrite_test.save
@overwrite_test.conflicting_method! "fast_value"
#=> true

## Invalid conflict strategy raises error during field definition
class InvalidStrategyTest < Familia::Horreum
  identifier_field :id
  field :id
  field :test_field, on_conflict: :invalid_strategy
end
#=!> ArgumentError

## Method conflict detection works with instance methods
class ConflictDetectionTest < Familia::Horreum
  identifier_field :id
  field :id

  def existing_method
    "exists"
  end

  field :existing_method, on_conflict: :raise
end
#=!> ArgumentError

## Conflict detection provides helpful error message
begin
  class ConflictMessageTest < Familia::Horreum
    identifier_field :id
    field :id

    def another_method
      "exists"
    end

    field :another_method, on_conflict: :raise
  end
rescue ArgumentError => e
  e.message.include?("another_method")
end
#=> true

## Method location information in error message when possible
begin
  class LocationInfoTest < Familia::Horreum
    identifier_field :id
    field :id

    def location_test_method
      "exists"
    end

    field :location_test_method, on_conflict: :raise
  end
rescue ArgumentError => e
  e.message.include?("defined at")
end
#=> true

## Skip strategy silently ignores conflicts
class SkipStrategyTest < Familia::Horreum
  identifier_field :id
  field :id

  def skip_method
    "original"
  end

  field :skip_method, on_conflict: :skip
end
@skip_test = SkipStrategyTest.new(id: 'skip1')
@skip_test.skip_method
#=> "original"

## Skip strategy doesn't create accessor methods when method exists
@skip_test.respond_to?(:skip_method=)
#=> false

## Warn strategy shows warning but continues with definition
class WarnStrategyTest < Familia::Horreum
  identifier_field :id
  field :id

  def warn_method
    "original"
  end

  field :warn_method, on_conflict: :warn
end
#=2> /WARNING/
@warn_test = WarnStrategyTest.new(id: 'warn1')
@warn_test.warn_method = "new_value"
@warn_test.warn_method
#=> "new_value"

## Fast method names must end with exclamation mark
class InvalidFastMethodTest < Familia::Horreum
  identifier_field :id
  field :id
  field :test_field, fast_method: :invalid_name
end
#=!> ArgumentError

## Fast method validation works with custom names
class ValidFastMethodTest < Familia::Horreum
  identifier_field :id
  field :id
  field :score, fast_method: :update_score_now!
end
@valid_fast = ValidFastMethodTest.new(id: 'valid1')
@valid_fast.respond_to?(:update_score_now!)
#=> true

## Method added hook detects conflicts after field definition
class MethodAddedHookTest < Familia::Horreum
  identifier_field :id
  field :id
  field :hook_test, on_conflict: :warn

  def hook_test
    "redefined_after"
  end
end
#=2> /WARNING/
#=2> /hook_test/
#=2> /redefined after field definition/

## Method added hook works with raise strategy too
class MethodAddedRaiseTest < Familia::Horreum
  identifier_field :id
  field :id
  field :raise_hook_test, on_conflict: :raise

  def raise_hook_test
    "redefined"
  end
end
#=!> ArgumentError

@overwrite_test.destroy! rescue nil
@skip_test.destroy! rescue nil
@warn_test.destroy! rescue nil
@valid_fast.destroy! rescue nil
@overwrite_test = nil
@skip_test = nil
@warn_test = nil
@valid_fast = nil
