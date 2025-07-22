# try/features/expiration_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test expiration feature functionality

class ParentExpiring < Familia::Horreum
  feature :expiration
  ttl 1000
end

class ChildExpiring < ParentExpiring
  identifier :id
  field :id
  ttl 1000
end

# Define a test class with expiration feature
class ExpiringTest < Familia::Horreum
  feature :expiration
  identifier :id
  field :id
  field :data
  ttl 300 # 5 minutes
end

# Setup test object
@test_obj = ExpiringTest.new
@test_obj.id = "expire_test_1"
@test_obj.data = "test data"

## Class has ttl method from feature
ExpiringTest.respond_to?(:ttl)
#=> true

## Class has default TTL set
ExpiringTest.ttl
#=> 300.0

## Can set different TTL on class
ExpiringTest.ttl(600)
ExpiringTest.ttl
#=> 600.0

## Object inherits class TTL
@test_obj.ttl
#=> 600.0

## Can set TTL on individual object
@test_obj.ttl = 120
@test_obj.ttl
#=> 120.0

## Object has update_expiration method
@test_obj.respond_to?(:update_expiration)
#=> true

## Can call update_expiration method
result = @test_obj.update_expiration(ttl: 180)
[result.class, result]
#=> [FalseClass, false]

## Child inherits parent TTL when not set
ChildExpiring.ttl
#=> 1000.0

## Can override parent TTL
ChildExpiring.ttl(500)
ChildExpiring.ttl
#=> 500.0

## Falls back to Familia.ttl when no class/parent TTL
class NoTTLTest < Familia::Horreum
  feature :expiration
  identifier :id
  field :id
end

NoTTLTest.ttl
#=> 0.0

# Cleanup
@test_obj.destroy!
ExpiringTest.ttl(300) # Reset to original
