# Test Horreum class methods

require_relative '../helpers/test_helpers'

## create factory method with existence checking
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
    field :age
  end

  result = user_class.respond_to?(:create) && user_class.respond_to?(:exists?)
  result
rescue StandardError => e
  false
end
#=> true

## multiget method is available
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end

  user_class.respond_to?(:multiget)
rescue StandardError => e
  false
end
#=> true

## find_keys method is available
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end

  user_class.respond_to?(:find_keys)
rescue StandardError => e
  false
end
#=> true
