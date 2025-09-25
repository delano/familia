# try/core/familia_new_methods_try.rb

require_relative '../helpers/test_helpers'

# Tests for new methods: demodularize, familia_name, and resolve_class

# Use the testable methods from the refactored module
String.include(Familia::Refinements::StylizeWordsMethods)

## demodularize removes module namespace from simple class name
'Customer'.demodularize
#=> 'Customer'

## demodularize removes module namespace from nested class name
'V2::Customer'.demodularize
#=> 'Customer'

## demodularize handles deep nesting
'My::Deep::Nested::Module::Customer'.demodularize
#=> 'Customer'

## demodularize handles single colon edge case
'::Customer'.demodularize
#=> 'Customer'

## demodularize returns original string when no modules
'SimpleClass'.demodularize
#=> 'SimpleClass'

## familia_name returns demodularized class name for Customer
Customer.familia_name
#=> 'Customer'

## familia_name returns demodularized class name for Session
Session.familia_name
#=> 'Session'

## familia_name returns demodularized class name for Bone
Bone.familia_name
#=> 'Bone'

## resolve_class returns the same class when given a Class
Familia.resolve_class(Customer)
#=> Customer

## resolve_class finds class by string name
Familia.resolve_class('Customer')
#=> Customer

## resolve_class finds class by symbol name
Familia.resolve_class(:Customer)
#=> Customer

## resolve_class handles CamelCase string conversion
Familia.resolve_class('CustomDomain')
#=> CustomDomain

## resolve_class handles snake_case symbol conversion
Familia.resolve_class(:CustomDomain)
#=> CustomDomain

## resolve_class raises error for invalid input
begin
  Familia.resolve_class(123)
rescue ArgumentError => e
  e.message
end
#=> "Expected Class, String, or Symbol, got Integer"

## resolve_class returns nil for unknown class name
Familia.resolve_class('NonExistentClass')
#=> nil

## resolve_class returns nil for unknown symbol
Familia.resolve_class(:NonExistentClass)
#=> nil
