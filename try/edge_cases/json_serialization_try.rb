# try/edge_cases/json_serialization_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Define a simple model with fields that should handle JSON data
class JsonTest < Familia::Horreum
  identifier :id
  field :id
  field :config      # This should be able to store Hash objects
  field :tags        # This should be able to store Array objects
  field :simple      # This should store simple strings as-is
end


## Test 1: Store a Hash - should serialize to JSON automatically
test_obj = JsonTest.new
test_obj.config = { theme: "dark", notifications: true, settings: { volume: 80 } }
test_obj.config
#=:> Hash

## Test 2: Store an Array - should serialize to JSON automatically
test_obj = JsonTest.new
test_obj.tags = ["ruby", "redis", "json", "familia"]
test_obj.tags
#=:> Array

## Test 3: Store a simple string - should remain as string
test_obj = JsonTest.new
test_obj.simple = "just a string"
test_obj.simple
#=:> String

## Save the object - this should call serialize_value and use to_json
test_obj = JsonTest.new 'a_unque_id'
test_obj.save
#=> true

## Verify what's actually stored in Database (raw)
test_obj = JsonTest.new
test_obj.id = "json_test_1"
test_obj.config = { theme: "dark", notifications: true, settings: { volume: 80 } }
test_obj.simple = "just a string"
test_obj.tags = ["ruby", "redis", "json", "familia"]
test_obj.save
test_obj.hgetall
#=> {"id"=>"json_test_1", "config"=>"{\"theme\":\"dark\",\"notifications\":true,\"settings\":{\"volume\":80}}", "tags"=>"[\"ruby\",\"redis\",\"json\",\"familia\"]", "simple"=>"just a string", "key"=>"json_test_1"}

## Test 4: Hash should be deserialized back to Hash
test_obj = JsonTest.new 'any_id_will_do'
puts "Config after refresh:"
puts test_obj.config
puts "Config class: "
[test_obj.config.class, test_obj.config]
##=> [Hash, {:theme=>"dark", :notifications=>true, :settings=>{:volume=>80}}]

## Test 5: Array should be deserialized back to Array
test_obj = JsonTest.new 'any_id_will_do'
puts "Tags after refresh:"
puts test_obj.tags.inspect
puts "Tags class: #{test_obj.tags.class}"
test_obj.tags.inspect
test_obj.tags
##=> ["ruby", "redis", "json", "familia"]

## Test 6: Simple string should remain a string (this works correctly)
test_obj = JsonTest.new 'any_id_will_do'
puts "Simple after refresh:"
puts test_obj.simple.inspect
puts "Simple class: #{test_obj.simple.class}"
[test_obj.simple.class, test_obj.simple]
##=> [String, "just a string"]

# Demonstrate the asymmetry:
test_obj = JsonTest.new 'any_id_will_do'
puts "\n=== ASYMMETRY DEMONSTRATION ==="
puts "Before save: config is #{test_obj.config.class}"
test_obj.config = { example: "data" }
puts "After assignment: config is #{test_obj.config.class}"
test_obj.save
puts "After save: config is still #{test_obj.config.class}"
test_obj.refresh!
puts "After refresh: config is now #{test_obj.config.class}!"
