# try/unit/data_types/json_stringkey_try.rb
#
# frozen_string_literal: true

# Comprehensive tests for Familia::JsonStringKey
# A StringKey variant that uses JSON serialization for type preservation.
# Unlike StringKey, does NOT support INCR/DECR/APPEND operations.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# ========================================
# Type Preservation Tests (Critical)
# ========================================

## JsonStringKey stores and retrieves Integer values with type preservation
@int_key = Familia::JsonStringKey.new 'test:json_string:integer'
@int_key.value = 42
@int_key.value
#=> 42

## JsonStringKey Integer has correct class
@int_key.value.class
#=> Integer

## JsonStringKey stores and retrieves zero (falsy but valid)
@zero_key = Familia::JsonStringKey.new 'test:json_string:zero'
@zero_key.value = 0
@zero_key.value
#=> 0

## JsonStringKey zero is Integer not nil
@zero_key.value.class
#=> Integer

## JsonStringKey stores and retrieves negative integers
@neg_key = Familia::JsonStringKey.new 'test:json_string:negative'
@neg_key.value = -99
@neg_key.value
#=> -99

## JsonStringKey stores and retrieves Float values (timestamps, currency, etc.)
@float_key = Familia::JsonStringKey.new 'test:json_string:float'
@float_key.value = 1704067200.123
@float_key.value
#=> 1704067200.123

## JsonStringKey Float has correct class
@float_key.value.class
#=> Float

## JsonStringKey stores and retrieves Float precision
@precision_key = Familia::JsonStringKey.new 'test:json_string:precision'
@precision_key.value = 3.14159265358979
@precision_key.value
#=> 3.14159265358979

## JsonStringKey stores and retrieves boolean true with type preservation
@true_key = Familia::JsonStringKey.new 'test:json_string:bool_true'
@true_key.value = true
@true_key.value
#=> true

## JsonStringKey boolean true has correct class
@true_key.value.class
#=> TrueClass

## JsonStringKey stores and retrieves boolean false with type preservation
@false_key = Familia::JsonStringKey.new 'test:json_string:bool_false'
@false_key.value = false
@false_key.value
#=> false

## JsonStringKey boolean false has correct class (not nil, not string)
@false_key.value.class
#=> FalseClass

## JsonStringKey stores and retrieves nil values
@nil_key = Familia::JsonStringKey.new 'test:json_string:nil_val'
@nil_key.value = nil
# After setting nil, the key is deleted so it returns the default (nil)
@nil_key.value
#=> nil

## JsonStringKey nil has correct class
@nil_key.value.class
#=> NilClass

## JsonStringKey stores and retrieves String values
@str_key = Familia::JsonStringKey.new 'test:json_string:string'
@str_key.value = 'hello world'
@str_key.value
#=> 'hello world'

## JsonStringKey String has correct class
@str_key.value.class
#=> String

## JsonStringKey stores and retrieves empty string
@empty_str_key = Familia::JsonStringKey.new 'test:json_string:empty_string'
@empty_str_key.value = ''
@empty_str_key.value
#=> ''

## JsonStringKey empty string is different from nil
@empty_str_key.value.nil?
#=> false

## JsonStringKey stores and retrieves Hash with type preservation
@hash_key = Familia::JsonStringKey.new 'test:json_string:hash'
@hash_key.value = { 'name' => 'test', 'count' => 5 }
@hash_key.value
#=> {'name'=>'test', 'count'=>5}

## JsonStringKey Hash has correct class
@hash_key.value.class
#=> Hash

## JsonStringKey Hash preserves nested types (integer value)
@hash_key.value['count']
#=> 5

## JsonStringKey Hash nested value has correct class
@hash_key.value['count'].class
#=> Integer

## JsonStringKey stores and retrieves Array with type preservation
@array_key = Familia::JsonStringKey.new 'test:json_string:array'
@array_key.value = [1, 'two', true, nil, 3.5]
@array_key.value
#=> [1, 'two', true, nil, 3.5]

## JsonStringKey Array has correct class
@array_key.value.class
#=> Array

## JsonStringKey stores nested structures (hash with arrays)
@nested_key = Familia::JsonStringKey.new 'test:json_string:nested'
@nested_key.value = { 'users' => [{ 'id' => 1 }, { 'id' => 2 }], 'active' => true }
@nested_key.value
#=> {'users'=>[{'id'=>1}, {'id'=>2}], 'active'=>true}

## JsonStringKey nested structure preserves all types
@nested_key.value['active'].class
#=> TrueClass

## JsonStringKey nested array element is Hash
@nested_key.value['users'][0].class
#=> Hash

## JsonStringKey nested array element has integer value
@nested_key.value['users'][0]['id']
#=> 1

# ========================================
# Basic Operations Tests
# ========================================

## JsonStringKey#dbkey returns correct key
@basic_key = Familia::JsonStringKey.new 'arbitrary:json:key'
@basic_key.dbkey
#=> 'arbitrary:json:key'

## JsonStringKey#value= sets a value and returns it
@basic_key.value = 'test value'
#=> 'test value'

## JsonStringKey#value retrieves the set value
@basic_key.value
#=> 'test value'

## JsonStringKey#set is alias for value=
@basic_key.set('another value')
@basic_key.value
#=> 'another value'

## JsonStringKey#get is alias for value
@basic_key.value = 'get test'
@basic_key.get
#=> 'get test'

## JsonStringKey#content is alias for value
@basic_key.content
#=> 'get test'

## JsonStringKey#setnx sets value only if key does not exist (success case)
@setnx_key = Familia::JsonStringKey.new 'test:json_string:setnx'
@setnx_key.delete!
@setnx_key.setnx('first value')
#=> true

## JsonStringKey#setnx value was set
@setnx_key.value
#=> 'first value'

## JsonStringKey#setnx does not overwrite existing value (failure case)
@setnx_key.setnx('second value')
#=> false

## JsonStringKey#setnx original value preserved
@setnx_key.value
#=> 'first value'

## JsonStringKey#del removes the key
@del_key = Familia::JsonStringKey.new 'test:json_string:del'
@del_key.value = 'to be deleted'
@del_key.del
#=> true

## JsonStringKey#del returns false when key does not exist
@del_key.del
#=> false

## JsonStringKey#delete! removes the key (returns count)
@del2_key = Familia::JsonStringKey.new 'test:json_string:del2'
@del2_key.value = 'to be deleted'
@del2_key.delete!
#=> 1

## JsonStringKey#empty? returns true when value is nil
@empty_check = Familia::JsonStringKey.new 'test:json_string:empty_check'
@empty_check.delete!
@empty_check.empty?
#=> true

## JsonStringKey#empty? returns false when value exists
@empty_check.value = 'not empty'
@empty_check.empty?
#=> false

# ========================================
# Conversion Methods Tests
# ========================================

## JsonStringKey#to_s returns deserialized value as string
@conv_key = Familia::JsonStringKey.new 'test:json_string:conversion'
@conv_key.value = 'string test'
@conv_key.to_s
#=> 'string test'

## JsonStringKey#to_s converts integer to string
@conv_key.value = 42
@conv_key.to_s
#=> '42'

## JsonStringKey#to_i converts string to integer
@conv_key.value = '123'
@conv_key.to_i
#=> 123

## JsonStringKey#to_i returns integer as-is
@conv_key.value = 456
@conv_key.to_i
#=> 456

## JsonStringKey#to_f converts string to float
@conv_key.value = '3.14'
@conv_key.to_f
#=> 3.14

## JsonStringKey#to_f returns float as-is
@conv_key.value = 2.718
@conv_key.to_f
#=> 2.718

# ========================================
# Default Value Handling Tests
# ========================================

## JsonStringKey with :default option returns default when key does not exist
@default_key = Familia::JsonStringKey.new 'test:json_string:with_default', default: 'default_value'
@default_key.delete!
@default_key.value
#=> 'default_value'

## JsonStringKey with :default option for integer
@default_int = Familia::JsonStringKey.new 'test:json_string:default_int', default: 100
@default_int.delete!
@default_int.value
#=> 100

## JsonStringKey with :default option still allows setting value
@default_key.value = 'custom value'
@default_key.value
#=> 'custom value'

## JsonStringKey :default with boolean false
@default_false = Familia::JsonStringKey.new 'test:json_string:default_false', default: false
@default_false.delete!
@default_false.value
#=> false

## JsonStringKey :default with zero
@default_zero = Familia::JsonStringKey.new 'test:json_string:default_zero', default: 0
@default_zero.delete!
@default_zero.value
#=> 0

# ========================================
# Edge Cases Tests
# ========================================

## JsonStringKey handles symbols by converting to string
@symbol_key = Familia::JsonStringKey.new 'test:json_string:symbol'
@symbol_key.value = :active
@symbol_key.value
#=> 'active'

## JsonStringKey handles very large integers
@large_int = Familia::JsonStringKey.new 'test:json_string:large_int'
@large_int.value = 9999999999999999999
@large_int.value
#=> 9999999999999999999

## JsonStringKey handles very small floats
@small_float = Familia::JsonStringKey.new 'test:json_string:small_float'
@small_float.value = 0.000000001
@small_float.value
#=> 0.000000001

## JsonStringKey handles unicode strings
@unicode_key = Familia::JsonStringKey.new 'test:json_string:unicode'
@unicode_key.value = 'Hello'
@unicode_key.value
#=> 'Hello'

## JsonStringKey handles special characters
@special_key = Familia::JsonStringKey.new 'test:json_string:special'
@special_key.value = "line1\nline2\ttab\"quote"
@special_key.value
#=> "line1\nline2\ttab\"quote"

## JsonStringKey handles deeply nested structure
@deep_key = Familia::JsonStringKey.new 'test:json_string:deep'
@deep_key.value = { 'a' => { 'b' => { 'c' => { 'd' => [1, 2, 3] } } } }
@deep_key.value['a']['b']['c']['d']
#=> [1, 2, 3]

# ========================================
# Registration Tests
# ========================================

## JsonStringKey is registered as :json_string
Familia::DataType.registered_types[:json_string]
#=> Familia::JsonStringKey

## JsonStringKey is registered as :json_stringkey
Familia::DataType.registered_types[:json_stringkey]
#=> Familia::JsonStringKey

# ========================================
# Familia Object Reference Tests
# ========================================

## JsonStringKey stores Familia object by identifier
@cust = Customer.new
@cust.custid = 'json_test_customer@example.com'
@ref_key = Familia::JsonStringKey.new 'test:json_string:familia_ref'
@ref_key.value = @cust
@ref_key.value
#=> 'json_test_customer@example.com'

# ========================================
# Type Comparison with StringKey
# ========================================

## StringKey does NOT preserve integer type (stores as string)
@str_compare = Familia::StringKey.new 'test:stringkey:compare'
@str_compare.value = 42
@str_compare.value.class
#=> String

## JsonStringKey DOES preserve integer type
@json_compare = Familia::JsonStringKey.new 'test:json_stringkey:compare'
@json_compare.value = 42
@json_compare.value.class
#=> Integer

## StringKey does NOT preserve boolean type
@str_bool = Familia::StringKey.new 'test:stringkey:bool'
@str_bool.value = true
@str_bool.value.class
#=> String

## JsonStringKey DOES preserve boolean type
@json_bool = Familia::JsonStringKey.new 'test:json_stringkey:bool'
@json_bool.value = true
@json_bool.value.class
#=> TrueClass

# ========================================
# Cleanup
# ========================================

@int_key.delete!
@zero_key.delete!
@neg_key.delete!
@float_key.delete!
@precision_key.delete!
@true_key.delete!
@false_key.delete!
@nil_key.delete!
@str_key.delete!
@empty_str_key.delete!
@hash_key.delete!
@array_key.delete!
@nested_key.delete!
@basic_key.delete!
@setnx_key.delete!
@empty_check.delete!
@conv_key.delete!
@default_key.delete!
@default_int.delete!
@default_false.delete!
@default_zero.delete!
@symbol_key.delete!
@large_int.delete!
@small_float.delete!
@unicode_key.delete!
@special_key.delete!
@deep_key.delete!
@ref_key.delete!
@str_compare.delete!
@json_compare.delete!
@str_bool.delete!
@json_bool.delete!
