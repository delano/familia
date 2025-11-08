# try/features/encrypted_fields/error_conditions_try.rb
#
# frozen_string_literal: true

# try/features/encryption_fields/error_conditions_try.rb

require 'base64'

require_relative '../../support/helpers/test_helpers'

# Setup encryption keys for error testing
@test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32)
}
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1

class ErrorTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

## Malformed JSON raises appropriate error
@model = ErrorTest.new(id: 'err-1')
@model.instance_variable_set(:@secret, 'not-json{]')
@model.secret
#=!> Familia::EncryptionError
#==> error.message.include?('Invalid JSON structure')

## Tampered auth tag fails decryption
@model.secret = 'valid-secret'
@valid_cipher = @model.secret.encrypted_value
@tampered = Familia::JsonSerializer.parse(@valid_cipher)
@tampered['auth_tag'] = Base64.strict_encode64('tampered' * 4)
@model.instance_variable_set(:@secret, Familia::JsonSerializer.dump(@tampered))

@model.secret
#=!> Familia::EncryptionError
#==> error.message.include?('Invalid auth_tag size')

## Missing encryption config raises on validation
@original_keys = Familia.config.encryption_keys
Familia.config.encryption_keys = nil
Familia::Encryption.validate_configuration!
Familia.config.encryption_keys = @original_keys
#=!> Familia::EncryptionError
#==> error.message.include?('No encryption keys configured')

## Invalid Base64 in stored data causes decryption failure
# Reset keys for this test since they were cleared in previous test
Familia.config.encryption_keys = @test_keys
@model.instance_variable_set(:@secret, '{"algorithm":"aes-256-gcm","nonce":"!!!invalid!!!","ciphertext":"test","auth_tag":"test","key_version":"v1"}')
@model.secret
#=!> Familia::EncryptionError
#==> error.message.include?('Invalid Base64 encoding')

## Derivation counter still increments on decryption errors
Familia::Encryption.reset_derivation_count!
# Ensure keys are available for this test
Familia.config.encryption_keys = @test_keys
@error_model = ErrorTest.new(id: 'err-counter')
# UnsortedSet valid JSON but with invalid base64 data to trigger decrypt failure after parsing
@error_model.instance_variable_set(:@secret, '{"algorithm":"aes-256-gcm","nonce":"dGVzdA==","ciphertext":"invalid-base64!!!","auth_tag":"dGVzdA==","key_version":"v1"}')
begin
  @error_model.secret
rescue
end
# Derivation attempted even if decrypt fails
Familia::Encryption.derivation_count.value
#=> 1

## Unsupported algorithm in encrypted data
# Ensure keys are available for this test
Familia.config.encryption_keys = @test_keys
@model.secret = 'test-data'
@cipher_data = Familia::JsonSerializer.parse(@model.secret.encrypted_value)
@cipher_data['algorithm'] = 'unsupported-algorithm'
@model.instance_variable_set(:@secret, Familia::JsonSerializer.dump(@cipher_data))

@model.secret
#=!> Familia::EncryptionError
#==> error.message.include?('Unsupported algorithm')

## Missing current key version causes validation error
@original_version = Familia.config.current_key_version
Familia.config.current_key_version = nil
Familia::Encryption.validate_configuration!
Familia.config.current_key_version = @original_version
#=!> Familia::EncryptionError
#==> error.message.include?('No current key version set')

## Invalid key version in encrypted data
# Ensure keys are available for this test
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1
@model.secret = 'test-data'
@cipher_with_bad_version = Familia::JsonSerializer.parse(@model.secret.encrypted_value)
@cipher_with_bad_version['key_version'] = 'nonexistent'
@model.instance_variable_set(:@secret, Familia::JsonSerializer.dump(@cipher_with_bad_version))
@model.secret
#=!> Familia::EncryptionError
#==> error.message.include?('No key for version: nonexistent')

## Empty string and nil values don't trigger encryption errors
@empty_model = ErrorTest.new(id: 'empty-test')
@empty_model.secret = ''
@empty_model.secret
#=> nil

## Nil assignment and retrieval
@empty_model.secret = nil
@empty_model.secret
#=> nil

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
