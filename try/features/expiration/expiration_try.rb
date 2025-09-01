# try/features/expiration_try.rb

require_relative '../../helpers/test_helpers'

Familia.debug = false

# Test expiration feature functionality

class ParentExpiring < Familia::Horreum
  feature :expiration
  default_expiration 1000
end

class ChildExpiring < ParentExpiring
  identifier_field :id
  field :id
  default_expiration 1000
end

# Define a test class with expiration feature
class ExpiringTest < Familia::Horreum
  feature :expiration
  identifier_field :id
  field :id
  field :data
  default_expiration 300 # 5 minutes
end

# Setup test object
@test_obj = ExpiringTest.new
@test_obj.id = 'expire_test_1'
@test_obj.data = 'test data'

## Class has default_expiration method from feature
ExpiringTest.respond_to?(:default_expiration)
#=> true

## Class has default expiration set
ExpiringTest.default_expiration
#=> 300.0

## Can set different default expiration on class
ExpiringTest.default_expiration(600)
ExpiringTest.default_expiration
#=> 600.0

## Object inherits class default expiration
@test_obj.default_expiration
#=> 600.0

## Can set default expiration on individual object
@test_obj.default_expiration = 120
@test_obj.default_expiration
#=> 120.0

## Object has update_expiration method
@test_obj.respond_to?(:update_expiration)
#=> true

## Can call update_expiration method
result = @test_obj.update_expiration(default_expiration: 180)
[result.class, result]
#=> [FalseClass, false]

## Child inherits parent default expiration when not set
ChildExpiring.default_expiration
#=> 1000.0

## Can override parent default expiration
ChildExpiring.default_expiration(500)
ChildExpiring.default_expiration
#=> 500.0

## Falls back to Familia.default_expiration when no class/parent default expiration
class NoDefaultExpirationTest < Familia::Horreum
  feature :expiration
  identifier_field :id
  field :id
end
NoDefaultExpirationTest.default_expiration
#=> 0.0

# Cleanup
@test_obj.destroy!
ExpiringTest.default_expiration(300) # Reset to original
