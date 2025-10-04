# Test reserved keyword handling

require_relative '../support/helpers/test_helpers'

## attempting to use ttl as field name causes error
TestClass = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :ttl  # This should cause an error
  field :default_expiration
end

user = TestClass.new(email: 'test@example.com', ttl: 3600)
user.save
result = user.ttl == 3600
user.delete!
result
#=!> StandardError

## prefixed field names work as expected
ExampleTestClass = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :secret_ttl
  field :user_db
  field :dbclient_config
end

user = ExampleTestClass.new(email: 'test@example.com')
user.secret_ttl = 3600
user.user_db = 5
user.dbclient_config = { host: 'localhost' }
user.save

result = user.secret_ttl == 3600 &&
         user.user_db == 5 &&
         user.dbclient_config.is_a?(Hash)

user.delete!
result
#=> true

## Reserved methods still work normally
TestClass3 = Class.new(Familia::Horreum) do
  # Note: Does not enable expiration feature
  identifier_field :email
  field :email
end

user = TestClass3.new(email: 'test@example.com')
user.save
user.delete!
user
# These should be available as methods even though we can't use them as field names
#=/=> _.respond_to?(:default_expiration)
#==> _.respond_to?(:logical_database)
#==> _.respond_to?(:dbclient)

## Attempting to pass default_expiration as a field value when instantiating,
## when expiration feature is enabled. It doesn't actually change the default
## expiration for the instance b/c "default_expiration" is not a regular field.
TestClassWithExpirationEnabled1 = Class.new(Familia::Horreum) do
  feature :expiration
  identifier_field :email
  field :email
end

user = TestClassWithExpirationEnabled1.new(email: 'test@example.com', default_expiration: 3600)
user.default_expiration
#=> 0

## Attempting to set default_expiration for an instance when
## the feature is enabled should work
TestClassWithExpirationEnabled2 = Class.new(Familia::Horreum) do
  feature :expiration
  identifier_field :email
  field :email
end

user = TestClassWithExpirationEnabled2.new(email: 'test@example.com')
user.default_expiration = 3601
user.default_expiration
#=> 3601

## Attempting to pass default_expiration as a field value when instantiating,
## when expiration feature is disabled and then trying to access that value
## simply raises a NoMethodError error.
TestClassWithExpirationDisabled = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
end

user = TestClassWithExpirationDisabled.new(email: 'test@example.com', default_expiration: 3600)
user.default_expiration
#=!> NoMethodError

## Attempting to add a field with a reserved name should raise an error
TestClassWithExpirationDisabled = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :default_expiration
end
##=!> NoMethodError

## prefixed field names work as expected
TestClass5 = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :secret_ttl
  field :user_db
  field :dbclient_config
end

user = TestClass5.new(email: 'test@example.com')
user.secret_ttl = 3600
user.user_db = 5
user.dbclient_config = { host: 'localhost' }
user.save

result = user.secret_ttl == 3600 &&
         user.user_db == 5 &&
         user.dbclient_config.is_a?(Hash)

user.delete!
result
#=> true

## reserved methods still work normally
TestClass6 = Class.new(Familia::Horreum) do
  feature :expiration
  identifier_field :email
  field :email
end

user = TestClass6.new(email: 'test@example.com')
user.save

# These should be available as methods even though we can't use them as field names
result = user.respond_to?(:default_expiration) &&
         user.respond_to?(:logical_database) &&
         user.respond_to?(:dbclient)

user.delete!
result
#=> true
