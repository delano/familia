# try/features/transient_fields/refresh_reset_try.rb
# Test that refresh! properly resets transient fields to nil

require_relative '../../helpers/test_helpers'

Familia.debug = false

Familia.dbclient.flushdb

class SecretService < Familia::Horreum
  identifier_field :name

  field :name
  field :endpoint_url

  transient_field :api_key
  transient_field :password
  transient_field :secret_token, as: :token
end

@service = SecretService.new
@service.name = 'test-service'
@service.endpoint_url = 'https://api.example.com'
@service.api_key = 'sk-1234567890abcdef'
@service.password = 'super-secret-password'
@service.token = 'token-xyz789'


## Verify class has the expected fields
SecretService.fields.sort
#=> [:api_key, :endpoint_url, :name, :password, :secret_token]

## Verify service was created successfully
@service.nil?
#=> false

## Save persistent fields to database
@service.save
#=> true

## Verify transient fields have values before refresh
@service.api_key.nil?
#=> false

## Verify transient fields are RedactedString instances
@service.api_key
#=:> RedactedString

## Verify transient fields will not expose the value like a string
@service.api_key.to_s
#=> '[REDACTED]'

## Verify transient fields will expose the value when asked
@service.api_key.value
#=> 'sk-1234567890abcdef'

## Verify password field has value before refresh
@service.password.nil?
#=> false

## Verify token alias has value before refresh
@service.token.nil?
#=> false

## Verify persistent fields have values before refresh
@service.name
#=> "test-service"

## Verify endpoint_url has value before refresh
@service.endpoint_url
#=> "https://api.example.com"

## Refresh! should reset transient fields to nil but keep persistent ones
@service.refresh!
#=> [:name, :endpoint_url]

## After refresh!, transient fields should be nil
@service.api_key.nil?
#=> true

## After refresh!, password should be nil
@service.password.nil?
#=> true

## After refresh!, token alias should be nil
@service.token.nil?
#=> true

## After refresh!, persistent fields should retain their values
@service.name
#=> "test-service"

## After refresh!, endpoint_url should retain its value
@service.endpoint_url
#=> "https://api.example.com"

## UnsortedSet transient fields again after refresh
@service.api_key = 'new-api-key-after-refresh'
@service.password = 'new-password-after-refresh'
@service.token = 'new-token-after-refresh'
#=> 'new-token-after-refresh'

## Verify transient fields have new values
@service.api_key.nil?
#=> false

## Verify they're still RedactedString instances
@service.api_key
#=:> RedactedString

## Another refresh! should reset them again
@service.refresh!
#=> [:name, :endpoint_url]

## Transient fields should be nil again
@service.api_key.nil?
#=> true

## Password should be nil again
@service.password.nil?
#=> true

## Token should be nil again
@service.token.nil?
#=> true

## But persistent fields should remain intact
@service.name
#=> "test-service"

## Endpoint URL should remain intact
@service.endpoint_url
#=> "https://api.example.com"

## Test refresh! with object that has no transient fields
class SimpleService < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  field :status
end

@no_transient = SimpleService.new('no-transient-test')
@no_transient.name = 'No Transient Service'
@no_transient.status = 'active'

# Save and refresh should work normally without transient fields
@no_transient.save
@no_transient.refresh!

# All fields should retain their values
@no_transient.id
#=> "no-transient-test"

## Name should be preserved
@no_transient.name
#=> "No Transient Service"

## Status should be preserved
@no_transient.status
#=> "active"


[@service, @no_transient].each(&:destroy!)
