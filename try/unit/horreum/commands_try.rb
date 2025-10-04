# try/horreum/commands_try.rb

# Test Horreum Valkey/Redis commands

require_relative '../../support/helpers/test_helpers'

## hget/hset operations
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
    field :score
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:hset) && user.respond_to?(:hget)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## increment/decrement operations not available
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
    field :score
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:incr) && user.respond_to?(:decr)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## field existence and key operations not available
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:key?)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## bulk field operations availability
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:hkeys) && user.respond_to?(:hvals) && user.respond_to?(:hgetall)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false
