# Test cross-component integration scenarios

require_relative '../support/helpers/test_helpers'

class TestUser < Familia::Horreum
  using Familia::Refinements::StylizeWords

  identifier_field :email
  field :email
  field :name
  feature :expiration
  feature :safe_dump
  set :tags

  default_expiration 3600
end


## Horreum with multiple features integration
user = TestUser.new(email: "test@example.com", name: "Integration Test")
user.save

# Test expiration feature
user.expire(1800)
ttl_works = user.current_expiration > 0

# Test safe_dump feature
safe_data = user.safe_dump
safe_dump_works = safe_data.is_a?(Hash)

result = ttl_works && safe_dump_works
user.delete!
result
#=> true

## Cannot generate a prefix for an anonymous class
user_class = Class.new(Familia::Horreum) do

end
user_class.prefix
#=!> Familia::Problem

## DataType relations with Horreum expiration
user_class = TestUser

user = user_class.new(email: "test@example.com")
user.save
user.expire(1800)

# Create related DataType
tags = user.tags
tags << "ruby" << "redis"

# Check if both exist
result = tags.exists? && user.exists?
user.delete!
result
#=> true
