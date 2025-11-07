# try/unit/familia_resolve_class_try.rb
#
# Unit tests for Familia.resolve_class method
#
# This test ensures the public API for resolving class references works
# correctly across different input types (Class, Symbol, String).
#
# Related to the fix for NoMethodError in participates_in where the private
# method member_by_config_name was being called directly instead of using
# the public resolve_class API.

require_relative '../support/helpers/test_helpers'

# Test class for resolution
class ResolveTestClass < Familia::Horreum
  identifier_field :id
  field :id
  field :name
end

## Test resolve_class with Class object returns the class unchanged
@resolved_class = Familia.resolve_class(ResolveTestClass)
@resolved_class == ResolveTestClass
#=> true

## Test resolve_class with Symbol returns the correct class
@resolved_symbol = Familia.resolve_class(:ResolveTestClass)
@resolved_symbol == ResolveTestClass
#=> true

## Test resolve_class with String returns the correct class
@resolved_string = Familia.resolve_class('ResolveTestClass')
@resolved_string == ResolveTestClass
#=> true

## Test resolve_class with lowercase symbol works (case-insensitive)
@resolved_lowercase = Familia.resolve_class(:resolvetestclass)
@resolved_lowercase == ResolveTestClass
#=> true

## Test resolve_class with lowercase string works (case-insensitive)
@resolved_lowercase_str = Familia.resolve_class('resolvetestclass')
@resolved_lowercase_str == ResolveTestClass
#=> true

## Test resolve_class with snake_case symbol works
@resolved_snake = Familia.resolve_class(:resolve_test_class)
@resolved_snake == ResolveTestClass
#=> true

## Test resolve_class with snake_case string works
@resolved_snake_str = Familia.resolve_class('resolve_test_class')
@resolved_snake_str == ResolveTestClass
#=> true

## Test resolve_class raises ArgumentError for invalid types
begin
  Familia.resolve_class(123)
  @raised = false
rescue ArgumentError => e
  @raised = true
  @error_message = e.message
end
@raised
#=> true

## Test error message is descriptive
@error_message.include?('Expected Class, String, or Symbol')
#=> true

## Test resolve_class returns nil for non-existent class
@nonexistent = Familia.resolve_class(:NonExistentClass)
@nonexistent.nil?
#=> true

## Test resolve_class is case-insensitive for existing classes
@case_variant1 = Familia.resolve_class(:RESOLVETESTCLASS)
@case_variant1 == ResolveTestClass
#=> true

## Test resolve_class handles mixed case strings
@case_variant2 = Familia.resolve_class('rEsOlVeTEsTcLaSs')
@case_variant2 == ResolveTestClass
#=> true

# Test with modularized class name
module ResolveTestModule
  class ModularClass < Familia::Horreum
    identifier_field :id
    field :id
  end
end

## Test resolve_class with modularized Symbol (without module prefix)
@modular_resolved = Familia.resolve_class(:ModularClass)
@modular_resolved == ResolveTestModule::ModularClass
#=> true

## Test resolve_class with modularized String (without module prefix)
@modular_resolved_str = Familia.resolve_class('ModularClass')
@modular_resolved_str == ResolveTestModule::ModularClass
#=> true

## Test resolve_class with snake_case modularized Symbol
@modular_snake = Familia.resolve_class(:modular_class)
@modular_snake == ResolveTestModule::ModularClass
#=> true

## Test resolve_class with Class object for modularized class
@modular_class_obj = Familia.resolve_class(ResolveTestModule::ModularClass)
@modular_class_obj == ResolveTestModule::ModularClass
#=> true
