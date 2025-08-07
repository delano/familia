# try/features/transient_fields_integration_try.rb

require_relative '../../lib/familia'


class SecretService < Familia::Horreum
  feature :transient_fields
  identifier_field :service_id

  field :service_id
  field :name
  field :endpoint_url
  transient_field :api_key
  transient_field :password
  transient_field :secret_token, as: :token
end

@service = SecretService.new
@service.service_id = 'test_service_1'
@service.name = 'Test API Service'
@service.endpoint_url = 'https://api.example.com'
@service.api_key = 'sk-1234567890abcdef'
@service.password = 'super_secret_password'
@service.token = 'token-xyz789'



## Class includes transient_fields feature
SecretService.feature(:transient_fields)
defined?(SecretService.feature)
#=> "method"

## Class has correct field definitions
SecretService.fields.sort
#=> [:api_key, :endpoint_url, :name, :password, :secret_token, :service_id]

## Persistent fields exclude transient ones
SecretService.persistent_fields.sort
#=> [:endpoint_url, :name, :service_id]

## Transient field definitions have correct category
SecretService.field_types[:api_key].category
#=> :transient

## Password field definition has correct category
SecretService.field_types[:password].category
#=> :transient

## Secret token field definition has correct category
SecretService.field_types[:secret_token].category
#=> :transient

## Regular field definition has correct category
SecretService.field_types[:name].category
#=> :field

## Transient field stores RedactedString object for api_key
@service.api_key.class
#=> RedactedString

## Transient field stores RedactedString object for password
@service.password.class
#=> RedactedString

## Transient field stores RedactedString object for token alias
@service.token.class
#=> RedactedString

## Regular field stores normal string value for name
@service.name.class
#=> String

## Regular field stores normal string value for endpoint_url
@service.endpoint_url.class
#=> String

## Transient field value is redacted in string representation
@service.api_key.to_s
#=> "[REDACTED]"

## Transient field value is redacted in inspect output
@service.password.inspect
#=> "[REDACTED]"

## Transient field can expose value securely through block
result = nil
@service.api_key.expose { |val| result = val.dup }
result
#=> "sk-1234567890abcdef"

## Transient field with custom method name exposes value correctly
result = nil
@service.token.expose { |val| result = val.dup }
result
#=> "token-xyz789"

## Setting transient field with existing RedactedString works
already_redacted = RedactedString.new("already_wrapped")
@service.password = already_redacted
@service.password.class
#=> RedactedString

## Serialization to_h only includes persistent fields
hash_result = @service.to_h
hash_result.keys.sort
#=> [:endpoint_url, :name, :service_id]

## Serialization to_h excludes api_key transient field
hash_result = @service.to_h
hash_result.key?("api_key")
#=> false

## Serialization to_h excludes password transient field
hash_result = @service.to_h
hash_result.key?("password")
#=> false

## Serialization to_h excludes secret_token transient field
hash_result = @service.to_h
hash_result.key?("secret_token")
#=> false

## Serialization to_a only includes persistent field values
array_result = @service.to_a
array_result.length
#=> 3

## Array contains values in persistent field order
array_result = @service.to_a
persistent_fields_values = SecretService.persistent_fields.map { |f| @service.send(SecretService.field_types[f].method_name) }
array_result == persistent_fields_values
#=> true

## Database persistence only stores persistent fields
@service.save
raw_data = @service.hgetall
raw_data.keys.sort
#=> ["endpoint_url", "name", "service_id"]

## Raw Database data excludes api_key transient field
raw_data = @service.hgetall
raw_data.key?("api_key")
#=> false

## Raw Database data excludes password transient field
raw_data = @service.hgetall
raw_data.key?("password")
#=> false

## Raw Database data excludes secret_token transient field
raw_data = @service.hgetall
raw_data.key?("secret_token")
#=> false

## Database refresh only loads persistent fields name
fresh_service = SecretService.new
fresh_service.service_id = 'test_service_1'
fresh_service.refresh!
fresh_service.name
#=> "Test API Service"

## Database refresh only loads persistent fields endpoint_url
fresh_service = SecretService.new
fresh_service.service_id = 'test_service_1'
fresh_service.refresh!
fresh_service.endpoint_url
#=> "https://api.example.com"

## Database refresh leaves transient api_key as nil
fresh_service = SecretService.new
fresh_service.service_id = 'test_service_1'
fresh_service.refresh!
fresh_service.api_key
#=> nil

## Database refresh leaves transient password as nil
fresh_service = SecretService.new
fresh_service.service_id = 'test_service_1'
fresh_service.refresh!
fresh_service.password
#=> nil

## Database refresh leaves transient token as nil
fresh_service = SecretService.new
fresh_service.service_id = 'test_service_1'
fresh_service.refresh!
fresh_service.token
#=> nil

## String interpolation with transient field shows redacted value
log_message = "Connecting to #{@service.name} with key: #{@service.api_key}"
log_message.include?("[REDACTED]")
#=> true

## String interpolation with transient field hides actual value
log_message = "Connecting to #{@service.name} with key: #{@service.api_key}"
log_message.include?("sk-1234567890abcdef")
#=> false

## Hash containing transient field shows redacted in string output
config_hash = {
  service: @service.name,
  key: @service.api_key,
  url: @service.endpoint_url
}
config_hash.to_s.include?("[REDACTED]")
#=> true

## Hash containing transient field hides actual value in string output
config_hash = {
  service: @service.name,
  key: @service.api_key,
  url: @service.endpoint_url
}
config_hash.to_s.include?("sk-1234567890abcdef")
#=> false

## Exception messages with transient fields are safe
begin
  raise StandardError, "Failed to authenticate with key: #{@service.api_key}"
rescue => e
  e.message.include?("[REDACTED]")
end
#=> true

## Multiple transient field assignment creates RedactedString instances
new_service = SecretService.new
new_service.service_id = 'test_service_2'
new_service.name = 'Another Service'
new_service.api_key = 'new-api-key-123'
new_service.password = 'new-password-456'
new_service.token = 'new-token-789'
[new_service.api_key, new_service.password, new_service.token].all? { |f| f.is_a?(RedactedString) }
#=> true

## Transient field can be set to nil value
new_service = SecretService.new
new_service.api_key = nil
new_service.api_key
#=> nil

## Persistent field definitions are correctly identified
SecretService.field_types.values.select(&:persistent?).map(&:field_name).sort
#=> [:endpoint_url, :name, :service_id]

## Transient field definitions are correctly identified
transient_fields = SecretService.field_types.values.reject(&:persistent?).map(&:field_name).sort
transient_fields
#=> [:api_key, :password, :secret_token]

## TEARDOWN

# Clean up Database
@service.destroy! if @service.exists?

# Clean up any test objects
@service = nil

# Force garbage collection to trigger any finalizers
GC.start
