# try/unit/familia_resolve_class_try.rb
#
# frozen_string_literal: true

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

# Test class in module for modularized class resolution
module ResolveTestModule
  class ModularClass < Familia::Horreum
    identifier_field :id
    field :id
  end
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

## Test resolve_class with PascalCase symbol works
@resolved_pascal_sym = Familia.resolve_class(:ResolveTestClass)
@resolved_pascal_sym == ResolveTestClass
#=> true

## Test resolve_class with PascalCase string works
@resolved_pascal_str = Familia.resolve_class('ResolveTestClass')
@resolved_pascal_str == ResolveTestClass
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

## Test resolve_class with variations of proper naming
# Note: All-caps or all-lowercase don't work because snake_case needs case boundaries
# Realistic usage: PascalCase, snake_case, or mixed-case with boundaries
@case_variant_snake = Familia.resolve_class('resolve_test_class')
@case_variant_snake == ResolveTestClass
#=> true

## Test resolve_class handles already snake_cased symbols
@already_snake = Familia.resolve_class(:resolve_test_class)
@already_snake == ResolveTestClass
#=> true

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
