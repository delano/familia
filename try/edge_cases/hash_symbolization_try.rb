# try/edge_cases/hash_symbolization_try.rb
#
# frozen_string_literal: true

# NOTE: These testcases are disabled b/c there's a shared context
# bug in Tryouts 3.1 that prevents the setup instance vars from
# being available to the testcases.

require_relative '../support/helpers/test_helpers'

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

## After save and refresh, default behavior uses string keys
@test_obj.refresh!
@test_obj.config.keys
#=> ["name", "age", "nested"]

## Nested hash also has string keys
@test_obj.config["nested"].keys
#=> ["theme"]

## Get raw JSON from Valkey/Redis
@raw_json = @test_obj.hget('config')
@raw_json.class
#=> String

## deserialize_value with default symbolize: false returns string keys
@string_result_default = @test_obj.deserialize_value(@raw_json)
@string_result_default.keys
#=> ["name", "age", "nested"]

## Nested hash in default result also has string keys
@string_result_default["nested"].keys
#=> ["theme"]

## deserialize_value with symbolize: true returns symbol keys
@symbol_result = @test_obj.deserialize_value(@raw_json, symbolize: true)
@symbol_result.keys
#=> [:name, :age, :nested]

## Nested hash in symbol result also has symbol keys
@symbol_result[:nested].keys
#=> [:theme]

## Values are preserved correctly with symbol keys
@symbol_result[:name]
#=> "John"

## Values are preserved correctly with string keys
@string_result_default['name']
#=> "John"

## Arrays are handled correctly too
@test_obj.config = [{ 'item' => 'value' }, 'string', 123]
@test_obj.save
@array_json = @test_obj.hget('config')
#=> "[{\"item\":\"value\"},\"string\",123]"

## Array with default (symbolize: false) keeps hash keys as strings
@string_array_default = @test_obj.deserialize_value(@array_json)
@string_array_default[0].keys
#=> ["item"]

## Array with symbolize: true converts hash keys to symbols
@symbol_array = @test_obj.deserialize_value(@array_json, symbolize: true)
@symbol_array[0].keys
#=> [:item]

## JSON-encoded string is parsed correctly
@test_obj.deserialize_value('"just a string"')
#=> "just a string"

## Non-JSON string returns as-is
@test_obj.deserialize_value('just a string')
#=> "just a string"

## JSON number is parsed to Integer
@test_obj.deserialize_value('42')
#=> 42

## Invalid JSON returns original string
@test_obj.deserialize_value('invalid json')
#=> "invalid json"

# Clean up
@test_obj.destroy!
