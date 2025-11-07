# try/integration/conventional_inheritance_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Define test classes in global namespace
class ::TestVehicle < Familia::Horreum
  identifier_field :vin
  field :vin
  field :make
  field :model
  field :year
  feature :expiration
  list :maintenance_log
  set :tags
end

class ::TestCar < ::TestVehicle
  field :doors
  field :fuel_type
end

class ::TestElectricCar < ::TestCar
  field :battery_capacity
  field :range_miles
end

class ::TestMotorcycle < ::TestVehicle
  field :engine_cc
  field :has_sidecar
end

class ::TestBaseModel < Familia::Horreum
end

class ::TestConcreteModel < ::TestBaseModel
  identifier_field :id
  field :name
end

## Creates a parent class with various configurations
@vehicle = TestVehicle.new(vin: 'ABC123', make: 'Toyota', model: 'Camry', year: 2020)

## Parent class has expected configuration
TestVehicle.identifier_field
#=> :vin

## Parent class has fields defined
TestVehicle.fields
#=> [:vin, :make, :model, :year]

## Parent class has features enabled
TestVehicle.features_enabled
#=> [:expiration]

## Child class inherits parent identifier_field
TestCar.identifier_field
#=> :vin

## Child class inherits parent fields and adds its own
TestCar.fields
#=> [:vin, :make, :model, :year, :doors, :fuel_type]

## Child class inherits parent features
TestCar.features_enabled
#=> [:expiration]

## Child instance works with inherited configuration
@car = TestCar.new(vin: 'DEF456', make: 'Honda', model: 'Civic', year: 2021, doors: 4, fuel_type: 'gasoline')
@car.identifier
#=> "DEF456"

## Child instance can access inherited fields
@car.make
#=> "Honda"

## Child instance can access new fields
@car.doors
#=> 4

## Child instance inherits DataType relationships
@car.maintenance_log.class
#=> Familia::ListKey

## Child instance can use inherited DataType relationships
@car.tags << 'reliable'
@car.tags.members
#=> ["reliable"]

## Grandchild inherits all ancestor configuration
TestElectricCar.identifier_field
#=> :vin

## Grandchild inherits all ancestor fields
TestElectricCar.fields
#=> [:vin, :make, :model, :year, :doors, :fuel_type, :battery_capacity, :range_miles]

## Grandchild inherits all ancestor features
TestElectricCar.features_enabled
#=> [:expiration]

## Grandchild instance works correctly
@electric = TestElectricCar.new(vin: 'TESLA123', make: 'Tesla', model: 'Model 3', doors: 4, battery_capacity: 75)
@electric.identifier
#=> "TESLA123"

## Parent and child classes remain independent after inheritance
TestVehicle.fields.size
#=> 4

## Child class has correct field count
TestCar.fields.size
#=> 6

## Grandchild class has correct field count
TestElectricCar.fields.size
#=> 8

## Parent field count unchanged after adding new child
TestVehicle.fields.size
#=> 4

## New child class has correct field count
TestMotorcycle.fields.size
#=> 6

## Child of empty parent inherits correctly
TestConcreteModel.identifier_field
#=> :id

## Child of empty parent has correct fields
TestConcreteModel.fields
#=> [:name]
