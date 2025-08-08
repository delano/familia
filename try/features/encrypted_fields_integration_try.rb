# try/features/encrypted_fields_integration_try.rb

# Test constants will be redefined in each test since variables don't persist

require_relative '../helpers/test_helpers'
require 'base64'


## Full model initialization with mixed field types works
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2

class FullSecureModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  field :name                    # Regular field
  field :email                   # Regular field for AAD
  encrypted_field :password      # Encrypted without AAD
  encrypted_field :api_token, aad_fields: [:email]  # Encrypted with AAD

  list :activity_log            # Regular list
  hashkey :metadata             # Regular hashkey
end

model = FullSecureModel.new(
  model_id: 'secure-123',
  name: 'Test User',
  email: 'test@secure.com'
)
[model.model_id, model.name, model.email]
#=> ['secure-123', 'Test User', 'test@secure.com']

## Setting encrypted fields works alongside regular fields
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2

class FullSecureModel2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  field :name
  field :email
  encrypted_field :password
  encrypted_field :api_token, aad_fields: [:email]
end

model = FullSecureModel2.new(
  model_id: 'secure-124',
  name: 'Test User 2',
  email: 'test2@secure.com'
)
model.password = 'secret-password-123'
model.api_token = 'api-token-abc-xyz'
[model.password, model.api_token]
#=> ['secret-password-123', 'api-token-abc-xyz']## Serialization via to_h includes plaintext (as expected for normal usage)

## repaired test
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class FullSecureModel3 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  encrypted_field :password
end

model = FullSecureModel3.new(model_id: 'secure-125')
model.password = 'secret-password-123'
hash_representation = model.to_h
# to_h calls getters, so it includes decrypted values
hash_representation.values.any? { |v| v.to_s.include?('secret-password-123') }
#=> true

## Instance variables contain encrypted data structure
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class FullSecureModel3b < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id
  field :model_id
  encrypted_field :password
end

model = FullSecureModel3b.new(model_id: 'secure-125b')
model.password = 'secret-password-123'
# Internal storage should be encrypted
encrypted_password = model.instance_variable_get(:@password)
encrypted_password.is_a?(String) && encrypted_password.include?('"algorithm":"xchacha20poly1305"')
#=> true

## Mixed data types work correctly with encrypted fields
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class FullSecureModel4 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  encrypted_field :password
  list :activity_log
  hashkey :metadata
end

model = FullSecureModel4.new(model_id: 'secure-126')
model.password = 'secure-pass'
model.activity_log << 'User logged in'
model.metadata['last_login'] = Time.now.to_i.to_s

[model.password, model.activity_log.size, model.metadata.has_key?('last_login')]
#=> ['secure-pass', 1, true]


# TEARDOWN
Thread.current[:familia_key_cache]&.clear if Thread.current[:familia_key_cache]
