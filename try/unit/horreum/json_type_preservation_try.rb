# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Setup: Define test model with various field types
class JsonTestModel < Familia::Horreum
  identifier_field :model_id
  field :model_id
  field :name           # String
  field :age            # Integer
  field :active         # Boolean
  field :score          # Float
  field :metadata       # Hash
  field :tags           # Array
  field :nested_data    # Hash with nested structures
end

@test_id = "json_test_#{Familia.now.to_i}"

## String fields preserve String type
@model = JsonTestModel.new(model_id: @test_id, name: "Test User")
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.name
#=> "Test User"

## String field returns String class
@loaded.name.class
#=> String

## Integer fields preserve Integer type (not String)
@model = JsonTestModel.new(model_id: @test_id, age: 35)
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.age
#=> 35

## Integer field returns Integer class (not String)
@loaded.age.class
#=> Integer

## Boolean true preserves TrueClass type (not String "true")
@model = JsonTestModel.new(model_id: @test_id, active: true)
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.active
#=> true

## Boolean true returns TrueClass
@loaded.active.class
#=> TrueClass

## Boolean false preserves FalseClass type (not String "false")
@model = JsonTestModel.new(model_id: @test_id, active: false)
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.active
#=> false

## Boolean false returns FalseClass
@loaded.active.class
#=> FalseClass

## Float fields preserve Float type
@model = JsonTestModel.new(model_id: @test_id, score: 98.6)
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.score
#=> 98.6

## Float field returns Float class
@loaded.score.class
#=> Float

## Hash fields preserve Hash structure
@model = JsonTestModel.new(model_id: @test_id, metadata: { "key" => "value", "count" => 42 })
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.metadata
#=> {"key"=>"value", "count"=>42}

## Hash field returns Hash class
@loaded.metadata.class
#=> Hash

## Array fields preserve Array structure and element types
@model = JsonTestModel.new(model_id: @test_id, tags: ["ruby", "redis", 123, true])
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.tags
#=> ["ruby", "redis", 123, true]

## Array field returns Array class
@loaded.tags.class
#=> Array

## Array preserves Integer element type
@loaded.tags[2].class
#=> Integer

## Array preserves Boolean element type
@loaded.tags[3].class
#=> TrueClass

## Nested Hash structures preserve types at all levels
@nested = {
  "user" => {
    "name" => "John",
    "age" => 30,
    "active" => true,
    "roles" => ["admin", "user"]
  },
  "count" => 5
}
@model = JsonTestModel.new(model_id: @test_id, nested_data: @nested)
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.nested_data["user"]["age"].class
#=> Integer

## Nested Hash Boolean preserved
@loaded.nested_data["user"]["active"].class
#=> TrueClass

## Nested Hash top-level Integer preserved
@loaded.nested_data["count"].class
#=> Integer
## Round-trip consistency: save → load → save → load maintains types
@model = JsonTestModel.new(
  model_id: @test_id,
  name: "Round Trip",
  age: 42,
  active: true,
  score: 99.9,
  tags: [1, 2, 3]
)
@model.save
@first_load = JsonTestModel.find(@test_id)
@first_load.save  # Re-save without modification
@second_load = JsonTestModel.find(@test_id)
[@second_load.age.class, @second_load.active.class, @second_load.tags[0].class]
#=> [Integer, TrueClass, Integer]

## batch_update preserves types
@model = JsonTestModel.new(model_id: @test_id)
@model.batch_update(name: "Batch", age: 50, active: false, tags: ["one", 2])
@loaded = JsonTestModel.find(@test_id)
[@loaded.name, @loaded.age, @loaded.active, @loaded.tags[1]]
#=> ["Batch", 50, false, 2]

## batch_update types verification
[@loaded.age.class, @loaded.active.class, @loaded.tags[1].class]
#=> [Integer, FalseClass, Integer]

## refresh! maintains type preservation
@model = JsonTestModel.new(model_id: @test_id, age: 25, active: true)
@model.save
# Modify directly in Redis to simulate external change
@model.dbclient.hset(@model.dbkey, "age", Familia::JsonSerializer.dump(30))
@model.refresh!
[@model.age, @model.age.class]
#=> [30, Integer]

## to_h returns string keys (external API compatibility)
@model = JsonTestModel.new(model_id: @test_id, name: "API Test", age: 40)
@hash = @model.to_h
@hash.keys.first.class
#=> String

## to_h has string key for name field
@hash.key?("name")
#=> true

## Nil values are handled correctly
@model = JsonTestModel.new(model_id: @test_id, name: "Nil Test", age: nil, active: nil)
@model.save
@loaded = JsonTestModel.find(@test_id)
[@loaded.age, @loaded.active]
#=> [nil, nil]

## Empty string preserved correctly
@model = JsonTestModel.new(model_id: @test_id, name: "")
@model.save
@loaded = JsonTestModel.find(@test_id)
@loaded.name
#=> ""

## Empty string has String class
@loaded.name.class
#=> String

## Zero values preserved with correct types
@model = JsonTestModel.new(model_id: @test_id, age: 0, score: 0.0)
@model.save
@loaded = JsonTestModel.find(@test_id)
[@loaded.age, @loaded.score]
#=> [0, 0.0]

## Zero Integer and Float have correct classes
[@loaded.age.class, @loaded.score.class]
#=> [Integer, Float]

# Teardown: Clean up test data
JsonTestModel.destroy!(@test_id) if JsonTestModel.exists?(@test_id)
