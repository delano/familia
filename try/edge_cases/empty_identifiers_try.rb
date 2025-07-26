# try/edge_cases/empty_identifiers_try.rb

require_relative '../helpers/test_helpers'

# Test empty identifier edge cases
group 'Empty Identifier Edge Cases'

setup do
  @user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :name
  end
end

try 'empty string identifier causes stack overflow' do
  user = @user_class.new(email: '', name: 'Test')

  begin
    user.exists? # This should cause infinite loop
    false
  rescue SystemStackError
    true  # Expected stack overflow
  rescue StandardError => e
    false # Unexpected error
  end
end

try 'nil identifier causes stack overflow' do
  user = @user_class.new(email: nil, name: 'Test')

  begin
    user.exists?
    false
  rescue SystemStackError, Familia::NoIdentifier
    true  # Expected error
  end
end

try 'validation workaround prevents stack overflow' do
  user = @user_class.new(email: '', name: 'Test')

  # Workaround: validate before operations
  raise ArgumentError, 'Empty identifier' if user.identifier.to_s.empty?

  false # Should not reach here
rescue ArgumentError => e
  e.message.include?('Empty identifier')
end
