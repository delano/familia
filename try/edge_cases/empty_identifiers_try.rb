# try/edge_cases/empty_identifiers_try.rb

# Test empty identifier edge cases

require_relative '../support/helpers/test_helpers'


## empty string identifier handling
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end
  user = user_class.new(email: '', name: 'Test')
  user.exists? # Test actual behavior with empty identifier
rescue SystemStackError
  'stack_overflow'  # Stack overflow occurred
rescue StandardError => e
  e.class.name  # Other error occurred
end
#=> "Familia::NoIdentifier"

## nil identifier handling
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end
  user = user_class.new(email: nil, name: 'Test')
  user.exists?
rescue SystemStackError
  'stack_overflow'
rescue Familia::NoIdentifier => e
  'no_identifier'
rescue StandardError => e
  e.class.name
end
#=> "no_identifier"

## empty identifier validation check
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end
  user = user_class.new(email: '', name: 'Test')
  # Check if identifier is empty
  user.identifier.to_s.empty?
rescue StandardError => e
  e.class.name
end
#=> true
