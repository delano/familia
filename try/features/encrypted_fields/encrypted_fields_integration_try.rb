# try/features/encrypted_fields/encrypted_fields_integration_try.rb
#
# frozen_string_literal: true

# try/features/encrypted_fields_integration_try.rb

# Test constants will be redefined in each test since variables don't persist

require_relative '../../support/helpers/test_helpers'
require 'base64'

# Clean up any leftover keys from a previous (possibly aborted) run so counts
# like activity_log.size stay deterministic. Scoped delete, not FLUSHDB
# (issue #283). Only FullSecureModel4 (secure-126) persists to the database;
# the class is defined mid-file, so match its prefix by string here.
delete_test_dbkeys('full_secure_model4:*')


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
# Persist scalar fields before mutating collections (see #278): a new, unsaved
# dirty parent raises on collection writes by default to avoid orphaned data.
@model4.save
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


# Per-field algorithm pin (issue #334): encrypted_field :name, algorithm: '...'
# selects the write algorithm for that field via Familia::Encryption.encrypt_with,
# independent of the registry's default provider. Reads stay envelope-driven, so
# pinning never affects ciphertext already at rest. See per_field_algorithm_try.rb
# for the full behavioral contract; the two checks below pin it end-to-end through
# the model field path.

## TEST 8: a field pinned to AES-256-GCM writes AES-256-GCM even though the
## registry default is XChaCha20-Poly1305 (rbnacl loaded)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AESIntegrationModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id

  field :model_id
  encrypted_field :secret_data, algorithm: 'aes-256-gcm' # Pin the write algorithm
end

@aes_model = AESIntegrationModel.new(model_id: 'aes-test')
@aes_model.secret_data = 'aes-gcm integration test'

# The pin is honored: the envelope records aes-256-gcm, not the default xchacha.
concealed_data = @aes_model.secret_data
encrypted_json = concealed_data.encrypted_value
parsed_data = Familia::JsonSerializer.parse(encrypted_json, symbolize_names: true)
[parsed_data[:algorithm], @aes_model.secret_data.reveal { |data| data }]
#=> ["aes-256-gcm", "aes-gcm integration test"]

## TEST 9: Provider-specific integration: AES-GCM with pinned algorithm
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AESIntegrationModel2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :model_id
  field :model_id
  encrypted_field :secret_data, algorithm: 'aes-256-gcm' # Pin the write algorithm
end

@aes_model2 = AESIntegrationModel2.new(model_id: 'aes-test')
@aes_model2.secret_data = 'aes-gcm integration test'  # Use setter, not manual encryption

# Verify algorithm and decryption
concealed_data = @aes_model2.secret_data
encrypted_json = concealed_data.encrypted_value
parsed_data = Familia::JsonSerializer.parse(encrypted_json, symbolize_names: true)
[parsed_data[:algorithm], @aes_model2.secret_data.reveal { |data| data }]
#=> ["aes-256-gcm", "aes-gcm integration test"]

# TEARDOWN
# Every test above installs its own keys inline. Clear the process-global
# encryption config so the next file in the shared-context run does not inherit
# them (issue #363).
clear_test_encryption_keys

# Remove the keys this file wrote (FullSecureModel4 secure-126 object hash,
# activity_log list, metadata hashkey, and any class-level registry entries).
# Scoped delete, not FLUSHDB (issue #283).
delete_test_dbkeys('full_secure_model4:*')
