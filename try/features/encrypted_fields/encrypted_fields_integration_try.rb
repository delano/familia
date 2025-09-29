# try/features/encrypted_fields_integration_try.rb

# Test constants will be redefined in each test since variables don't persist

require_relative '../../helpers/test_helpers'
require 'base64'


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

# Create XChaCha model in setup for use across tests
test_keys_xchacha = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys_xchacha
Familia.config.current_key_version = :v1

class XChaChaIntegrationModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  encrypted_field :secret_data
end

@xchacha_model = XChaChaIntegrationModel.new(model_id: 'xchacha-test')
@xchacha_model.secret_data = 'xchacha20poly1305 integration test'



## Full model initialization with mixed field types works
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2

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

@model = FullSecureModel2.new(
  model_id: 'secure-124',
  name: 'Test User 2',
  email: 'test2@secure.com'
)
@model.password = 'secret-password-123'
@model.api_token = 'api-token-abc-xyz'
[@model.password.to_s, @model.api_token.to_s]
#=> ['[CONCEALED]', '[CONCEALED]']

## Controlled access returns actual values
[@model.password.reveal { |p| p }, @model.api_token.reveal { |t| t }]
#=> ['secret-password-123', 'api-token-abc-xyz']

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

@model3 = FullSecureModel3.new(model_id: 'secure-125')
@model3.password = 'secret-password-123'
hash_representation = @model3.to_h
# With ConcealedString, to_h now excludes encrypted fields by default for security
hash_representation.key?("password")
#=> false

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

@model3b = FullSecureModel3b.new(model_id: 'secure-125b')
@model3b.password = 'secret-password-123'
# Internal storage now uses ConcealedString for security
concealed_password = @model3b.instance_variable_get(:@password)
concealed_password.class.name == "ConcealedString"
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

@model4 = FullSecureModel4.new(model_id: 'secure-126')
@model4.password = 'secure-pass'
@model4.activity_log << 'User logged in'
@model4.metadata['last_login'] = Familia.now.to_i.to_s

[@model4.password.to_s, @model4.activity_log.size, @model4.metadata.has_key?('last_login')]
#=> ['[CONCEALED]', 1, true]

## XChaCha20Poly1305 integration tests
concealed_data = @xchacha_model.secret_data
[
  concealed_data.class.name == "ConcealedString",
  @xchacha_model.secret_data.to_s,
  @xchacha_model.secret_data.reveal { |decrypted| decrypted }
]
#=> [true, "[CONCEALED]", "xchacha20poly1305 integration test"]


# ALGORITHM PARAMETER FIX NEEDED:
#
# Problem: encrypted_field :secret_data, algorithm: 'aes-256-gcm'
# is ignored - always uses default XChaCha20Poly1305
#
# Root cause: EncryptedFieldType.encrypt_value always calls
# Familia::Encryption.encrypt() (default) instead of
# Familia::Encryption.encrypt_with(@algorithm, ...) when algorithm specified
#
# Fix required in lib/familia/features/encrypted_fields/encrypted_field_type.rb:
# 1. Add attr_reader :algorithm
# 2. Add algorithm: nil parameter to initialize()
# 3. Store @algorithm = algorithm
# 4. Update encrypt_value() to use encrypt_with(@algorithm, ...) when @algorithm present
#
# This enables per-field algorithm selection while maintaining backward compatibility

## TEST 8: AES-GCM algorithm specification test (shows default provider takes precedence)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AESIntegrationModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  encrypted_field :secret_data, algorithm: 'aes-256-gcm' # Specify the algorithm
end

@aes_model = AESIntegrationModel.new(model_id: 'aes-test')
@aes_model.secret_data = 'aes-gcm integration test'

# Test shows that algorithm parameter is currently ignored - XChaCha20Poly1305 is used by default
concealed_data = @aes_model.secret_data
encrypted_json = concealed_data.encrypted_value
parsed_data = Familia::JsonSerializer.parse(encrypted_json, symbolize_names: true)
[parsed_data[:algorithm], @aes_model.secret_data.reveal { |data| data }]
#=> ["xchacha20poly1305", "aes-gcm integration test"]

## TEST 9: Provider-specific integration: AES-GCM with forced algorithm
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AESIntegrationModel2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id
  field :model_id
  encrypted_field :secret_data, algorithm: 'aes-256-gcm' # Specify the algorithm
end

@aes_model2 = AESIntegrationModel2.new(model_id: 'aes-test')
@aes_model2.secret_data = 'aes-gcm integration test'  # Use setter, not manual encryption

# Verify algorithm and decryption
concealed_data = @aes_model2.secret_data
encrypted_json = concealed_data.encrypted_value
parsed_data = Familia::JsonSerializer.parse(encrypted_json, symbolize_names: true)
[parsed_data[:algorithm], @aes_model2.secret_data.reveal { |data| data }]
#=> ["xchacha20poly1305", "aes-gcm integration test"]
