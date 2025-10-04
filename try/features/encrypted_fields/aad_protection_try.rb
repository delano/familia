# try/features/encryption_fields/aad_protection_try.rb

require 'concurrent'
require 'base64'

require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class AADProtectedModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :email
  encrypted_field :api_key, aad_fields: [:email]
end

# Clean test environment
Familia.dbclient.flushdb

## AAD prevents field substitution attacks - proper cross-record test
@victim = AADProtectedModel.new(id: 'victim-1', email: 'victim@example.com')
@victim.save  # Need to save first for AAD to be active
@victim.api_key = 'victim-secret-key'
@victim.save  # Save the encrypted value

# Extract the raw encrypted JSON data (not the ConcealedString object)
@victim_encrypted_data = @victim.api_key.encrypted_value

# Create an attacker record with different AAD context (different email)
@attacker = AADProtectedModel.new(id: 'attacker-1', email: 'attacker@evil.com')
@attacker.save  # Need to save for AAD to be active

# Simulate database tampering: set attacker's field to victim's encrypted data
# This simulates what an attacker with database access might try to do
@attacker.instance_variable_set(:@api_key,
  ConcealedString.new(@victim_encrypted_data, @attacker, @attacker.class.field_types[:api_key]))

# Attempt to decrypt should fail due to AAD mismatch
@result1 = begin
  decrypted_value = nil
  @attacker.api_key.reveal { |plaintext| decrypted_value = plaintext }
  "UNEXPECTED SUCCESS: #{decrypted_value}"
rescue Familia::EncryptionError => error
  error.class.name
end
@result1
#=> "Familia::EncryptionError"

## Verify error message indicates decryption failure
@result2 = begin
  @attacker.api_key.reveal { |plaintext| plaintext }
  "No error occurred"
rescue Familia::EncryptionError => error
  error.message.include?('Decryption failed')
end
@result2
#=> true

## Cross-record attack with same email (should still fail due to different identifiers)
victim2 = AADProtectedModel.new(id: 'victim-2', email: 'shared@example.com')
victim2.save
victim2.api_key = 'victim2-secret'
victim2.save

attacker2 = AADProtectedModel.new(id: 'attacker-2', email: 'shared@example.com')  # Same email!
attacker2.save

# Extract victim's encrypted data and try to decrypt with attacker's context
victim2_encrypted_data = victim2.api_key.encrypted_value
attacker2.instance_variable_set(:@api_key,
  ConcealedString.new(victim2_encrypted_data, attacker2, attacker2.class.field_types[:api_key]))

# Should fail because identifier is part of AAD even when aad_fields match
@result3 = begin
  attacker2.api_key.reveal { |plaintext| plaintext }
  "UNEXPECTED SUCCESS"
rescue Familia::EncryptionError => error
  error.class.name
end
@result3
#=> "Familia::EncryptionError"

## Without saving, AAD is not enforced (no database context)
unsaved_model = AADProtectedModel.new(id: 'unsaved-1', email: 'test@example.com')
unsaved_model.api_key = 'test-key'

# Change email after encryption but before save - should still work
unsaved_model.email = 'changed@example.com'
decrypted = nil
unsaved_model.api_key.reveal { |plaintext| decrypted = plaintext }
decrypted
#=> "test-key"

## Cross-model attack with raw encrypted JSON
# Demonstrate that raw encrypted data can't be moved between models
@json_victim = AADProtectedModel.new(id: 'json-victim-1', email: 'jsonvictim@example.com')
@json_victim.save
@json_victim.api_key = 'json-victim-secret'

# Get the raw encrypted JSON and create a new ConcealedString for different record
@raw_encrypted_json = @json_victim.api_key.encrypted_value
@json_attacker = AADProtectedModel.new(id: 'json-attacker-1', email: 'jsonattacker@evil.com')
@json_attacker.save

# Create ConcealedString with stolen encrypted JSON for the attacker
@fake_concealed = ConcealedString.new(@raw_encrypted_json, @json_attacker, @json_attacker.class.field_types[:api_key])

# Attempt decryption should fail
@result4 = begin
  @fake_concealed.reveal { |plaintext| plaintext }
  "UNEXPECTED SUCCESS"
rescue Familia::EncryptionError => error
  error.class.name
end
@result4
#=> "Familia::EncryptionError"

## Successful decryption with correct context (control test)
legitimate_user = AADProtectedModel.new(id: 'legitimate-1', email: 'legit@example.com')
legitimate_user.save
legitimate_user.api_key = 'legitimate-secret'
legitimate_user.save

# Normal decryption should work
decrypted_legit = nil
legitimate_user.api_key.reveal { |plaintext| decrypted_legit = plaintext }
decrypted_legit
#=> "legitimate-secret"

# Cleanup
Familia.dbclient.flushdb
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
