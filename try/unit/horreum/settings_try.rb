# try/horreum/settings_try.rb

# Test Horreum settings

require_relative '../../support/helpers/test_helpers'

## database selection inheritance
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :name
  logical_database 5
end

user_class.new(email: "test@example.com")
#==> _.logical_database == 5

## custom serialization methods
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :name
end

user_class.new(email: "test@example.com")
#==> _.respond_to?(:dump_method)
#==> _.respond_to?(:load_method)

## redisuri generation with suffix
user_class = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
end

user = user_class.new(email: "test@example.com")
uri = user.redisuri("suffix")

uri.include?("suffix")
#=!> StandardError
