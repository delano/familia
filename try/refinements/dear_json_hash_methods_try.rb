# try/refinements/dear_json_hash_methods_try.rb

require_relative '../helpers/test_helpers'

class TestHashWithDearJson < Hash
  include Familia::Refinements::DearJsonHashMethods
end

class TestObjectWithAsJson
  def initialize(name)
    @name = name
  end

  def as_json(options = nil)
    { name: @name, type: 'test_object' }
  end
end

## Can create a hash with DearJson methods
test_hash = TestHashWithDearJson.new
test_hash[:key] = 'value'
test_hash.respond_to?(:to_json)
#=> true

## to_json converts hash to JSON string using JsonSerializer
test_hash = TestHashWithDearJson.new
test_hash[:simple] = 'value'
test_hash[:number] = 42
json_result = test_hash.to_json
json_result
#=:> String

## to_json handles objects with as_json methods
test_hash = TestHashWithDearJson.new
test_obj = TestObjectWithAsJson.new('test')
test_hash[:object] = test_obj
test_hash[:simple] = 'value'
json_result = test_hash.to_json
json_result
#=~> /test_object/

## as_json returns the hash itself
test_hash = TestHashWithDearJson.new
test_hash[:key] = 'value'
result = test_hash.as_json
result == test_hash
#=> true

## as_json accepts options parameter
test_hash = TestHashWithDearJson.new
test_hash[:key] = 'value'
result = test_hash.as_json(some_option: true)
result == test_hash
#=> true
