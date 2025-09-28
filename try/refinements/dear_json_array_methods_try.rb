# try/refinements/dear_json_array_methods_try.rb

require_relative '../helpers/test_helpers'

class TestArrayWithDearJson < Array
  include Familia::Refinements::DearJsonArrayMethods
end

class TestObjectWithAsJson
  def initialize(name)
    @name = name
  end

  def as_json(options = nil)
    { name: @name, type: 'test_object' }
  end
end

## Can create an array with DearJson methods
test_array = TestArrayWithDearJson.new
test_array << 'value'
test_array.respond_to?(:to_json)
#=> true

## to_json converts array to JSON string using JsonSerializer
test_array = TestArrayWithDearJson.new
test_array << 'simple'
test_array << 42
json_result = test_array.to_json
json_result.class
#=> String

## to_json handles objects with as_json methods
test_array = TestArrayWithDearJson.new
test_obj = TestObjectWithAsJson.new('test')
test_array << test_obj
test_array << 'simple'
json_result = test_array.to_json
json_result.include?('test_object')
#=> true

## as_json returns the array itself
test_array = TestArrayWithDearJson.new
test_array << 'value'
result = test_array.as_json
result == test_array
#=> true

## as_json accepts options parameter
test_array = TestArrayWithDearJson.new
test_array << 'value'
result = test_array.as_json(some_option: true)
result == test_array
#=> true
