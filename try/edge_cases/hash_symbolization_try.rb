# try/edge_cases/hash_symbolization_try.rb

# NOTE: These testcases are disabled b/c there's a shared context
# bug in Tryouts 3.1 that prevents the setup instance vars from
# being available to the testcases.

require_relative '../helpers/test_helpers'

Familia.debug = false

# Test the updated deserialize_value method
class SymbolizeTest < Familia::Horreum
  identifier_field :id
  field :id
  field :config
end

@test_hash = { 'name' => 'John', 'age' => 30, 'nested' => { 'theme' => 'dark' } }
@test_obj = SymbolizeTest.new
@test_obj.id = 'symbolize_test_1'
@test_obj.config = @test_hash
@test_obj.save

## Original hash has string keys
@test_hash.keys
#=> ["name", "age", "nested"]

## After save and refresh, default behavior uses symbol keys
@test_obj.refresh!
@test_obj.config.keys
#=> [:name, :age, :nested]

## Nested hash also has symbol keys
@test_obj.config[:nested].keys
#=> [:theme]

## Get raw JSON from Redis
@raw_json = @test_obj.hget('config')
@raw_json.class
#=> String

## deserialize_value with default symbolize: true returns symbol keys
@symbol_result = @test_obj.deserialize_value(@raw_json)
@symbol_result.keys
#=> [:name, :age, :nested]

## Nested hash in symbol result also has symbol keys
@symbol_result[:nested].keys
#=> [:theme]

## deserialize_value with symbolize: false returns string keys
@string_result = @test_obj.deserialize_value(@raw_json, symbolize: false)
@string_result.keys
#=> ["name", "age", "nested"]

## Nested hash in string result also has string keys
@string_result['nested'].keys
#=> ["theme"]

## Values are preserved correctly in both cases
@symbol_result[:name]
#=> "John"

## String keys also work correctly
@string_result['name']
#=> "John"

## Arrays are handled correctly too
@test_obj.config = [{ 'item' => 'value' }, 'string', 123]
@test_obj.save
@array_json = @test_obj.hget('config')
#=> "[{\"item\":\"value\"},\"string\",123]"

## Array with symbolize: true converts hash keys to symbols
@symbol_array = @test_obj.deserialize_value(@array_json)
@symbol_array[0].keys
#=> [:item]

## Array with symbolize: false keeps hash keys as strings
@string_array = @test_obj.deserialize_value(@array_json, symbolize: false)
@string_array[0].keys
#=> ["item"]

## Non-hash/array values are returned as-is
@test_obj.deserialize_value('"just a string"')
#=> "\"just a string\""

## Non-hash/array values are returned as-is
@test_obj.deserialize_value('just a string')
#=> "just a string"

## A stringified number is still a stringified number
@test_obj.deserialize_value('42')
#=> "42"

## Invalid JSON returns original string
@test_obj.deserialize_value('invalid json')
#=> "invalid json"

# Clean up
@test_obj.destroy!
