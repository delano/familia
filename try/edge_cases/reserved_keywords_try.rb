# Test reserved keyword handling

require_relative '../helpers/test_helpers'

## attempting to use ttl as field name causes error
TestClass = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :default_expiration
end

user = TestClass.new(email: 'test@example.com', ttl: 3600)
user.save
result = user.ttl == 3600
user.delete!
result
#=!> StandardError

## prefixed field names work as expected
TestClass2 = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :secret_ttl
  field :user_db
  field :dbclient_config
end

user = TestClass2.new(email: 'test@example.com')
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


## Attempting to set default_expiration on an instance with expiration feature enabled
TestClass4 = Class.new(Familia::Horreum) do
  feature :expiration
  identifier_field :email
  field :email
  field :default_expiration
end

user = TestClass4.new(email: 'test@example.com', default_expiration: 3600)
user.save
user.delete!
user
#==> _.default_expiration == 3600

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
