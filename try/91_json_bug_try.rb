# try/91_json_bug_try.rb

require_relative '../lib/familia'
require_relative './test_helpers'

Familia.debug = false

# Define a simple model with fields that should handle JSON data
class JsonTest < Familia::Horreum
  identifier :id
  field :id
  field :config      # This should be able to store Hash objects
  field :tags        # This should be able to store Array objects
  field :simple      # This should store simple strings as-is
end

# Create an instance with JSON data
@test_obj = JsonTest.new
@test_obj.id = "json_test_1"

## Test 1: Store a Hash - should serialize to JSON automatically
@test_obj.config = { theme: "dark", notifications: true, settings: { volume: 80 } }
@test_obj.config.class
#=> Hash

## Test 2: Store an Array - should serialize to JSON automatically
@test_obj.tags = ["ruby", "redis", "json", "familia"]
@test_obj.tags.class
#=> Array

## Test 3: Store a simple string - should remain as string
@test_obj.simple = "just a string"
@test_obj.simple.class
#=> String

## Save the object - this should call serialize_value and use to_json
@test_obj.save
#=> true

## Verify what's actually stored in Redis (raw)
raw_data = @test_obj.hgetall
puts "Raw Redis data:"
raw_data
#=> {"id"=>"json_test_1", "config"=>"{\"theme\":\"dark\",\"notifications\":true,\"settings\":{\"volume\":80}}", "tags"=>"[\"ruby\",\"redis\",\"json\",\"familia\"]", "simple"=>"just a string", "key"=>"json_test_1"}

## BUG: After refresh, JSON data comes back as strings instead of parsed objects
@test_obj.refresh!
#=> [:id, :config, :tags, :simple, :key]

## Test 4: Hash should be deserialized back to Hash
puts "Config after refresh:"
puts @test_obj.config
puts "Config class: "
[@test_obj.config.class, @test_obj.config]
#=> [Hash, {:theme=>"dark", :notifications=>true, :settings=>{:volume=>80}}]

## Test 5: Array should be deserialized back to Array
puts "Tags after refresh:"
puts @test_obj.tags.inspect
puts "Tags class: #{@test_obj.tags.class}"
@test_obj.tags.inspect
@test_obj.tags
#=> ["ruby", "redis", "json", "familia"]

## Test 6: Simple string should remain a string (this works correctly)
puts "Simple after refresh:"
puts @test_obj.simple.inspect
puts "Simple class: #{@test_obj.simple.class}"
[@test_obj.simple.class, @test_obj.simple]
#=> [String, "just a string"]

# Demonstrate the asymmetry:
puts "\n=== ASYMMETRY DEMONSTRATION ==="
puts "Before save: config is #{@test_obj.config.class}"
@test_obj.config = { example: "data" }
puts "After assignment: config is #{@test_obj.config.class}"
@test_obj.save
puts "After save: config is still #{@test_obj.config.class}"
@test_obj.refresh!
puts "After refresh: config is now #{@test_obj.config.class}!"

# Clean up
@test_obj.destroy!
