# try/horreum/class_methods_try.rb

# Test Horreum class methods

require_relative '../helpers/test_helpers'

TestUser = Class.new(Familia::Horreum) do
  identifier_field :email
  field :email
  field :name
  field :age
end

module AnotherModuleName
  AnotherTestUser = Class.new(Familia::Horreum) do
  end
end

## create factory method with existence checking
TestUser
#==> _.respond_to?(:create)
#==> _.respond_to?(:exists?)

## multiget method is available
TestUser
#==> _.respond_to?(:multiget)

## find_keys method is available
TestUser
#==> _.respond_to?(:find_keys)

## config name turns a top-level class into a symbol
TestUser.config_name.to_sym
#=> :test_user

## config name turns the fully qualified class into a symbol, but just the right most class
AnotherModuleName::AnotherTestUser.config_name.to_sym
#=> :another_test_user
