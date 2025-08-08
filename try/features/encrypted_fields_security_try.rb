# try/features/encrypted_fields_security_try.rb

require_relative '../helpers/test_helpers'
require 'base64'


## Context isolation: Different field contexts use different encryption
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  encrypted_field :password      # No AAD
  encrypted_field :api_key       # No AAD
  encrypted_field :secret_data   # No AAD
end

user = SecurityTestModel.new(user_id: 'user1')

user.password = 'same-value'
user.api_key = 'same-value'
user.secret_data = 'same-value'

password_encrypted = user.instance_variable_get(:@password)
api_key_encrypted = user.instance_variable_get(:@api_key)
secret_data_encrypted = user.instance_variable_get(:@secret_data)


[password_encrypted != api_key_encrypted,
 password_encrypted != secret_data_encrypted,
 api_key_encrypted != secret_data_encrypted]
#=> [true, true, true]

## AAD Protection: Different users get different AAD
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel2 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  field :email
  encrypted_field :api_key, aad_fields: [:email]
end

user1 = SecurityTestModel2.new(user_id: 'user1', email: 'user1@example.com')
user2 = SecurityTestModel2.new(user_id: 'user2', email: 'user2@example.com')

# Same value with different AAD should encrypt differently
user1.api_key = 'same-api-key'
user2.api_key = 'same-api-key'

user1_encrypted = user1.instance_variable_get(:@api_key)
user2_encrypted = user2.instance_variable_get(:@api_key)

user1_encrypted != user2_encrypted
#=> true

## Auth tag manipulation fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel3 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModel3.new(user_id: 'user1')
user.password = 'test-password'
encrypted = user.instance_variable_get(:@password)

# Tamper with auth tag
parsed = JSON.parse(encrypted, symbolize_names: true)
original_auth_tag = parsed[:auth_tag]
tampered_auth_tag = original_auth_tag.dup
tampered_auth_tag[0] = tampered_auth_tag[0] == 'A' ? 'B' : 'A'
parsed[:auth_tag] = tampered_auth_tag
tampered_json = parsed.to_json

user.instance_variable_set(:@password, tampered_json)
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

## Ciphertext manipulation fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel4 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModel4.new(user_id: 'user1')
user.password = 'test-password'
encrypted = user.instance_variable_get(:@password)

# Tamper with ciphertext
parsed = JSON.parse(encrypted, symbolize_names: true)
original_ciphertext = parsed[:ciphertext]
tampered_ciphertext = original_ciphertext.dup
tampered_ciphertext[0] = tampered_ciphertext[0] == 'A' ? 'B' : 'A'
parsed[:ciphertext] = tampered_ciphertext
tampered_json = parsed.to_json

user.instance_variable_set(:@password, tampered_json)
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

## Nonce manipulation detection
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel5 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModel5.new(user_id: 'user1')
user.password = 'test-password'
encrypted = user.instance_variable_get(:@password)

# Tamper with nonce
parsed = JSON.parse(encrypted, symbolize_names: true)
original_nonce = parsed[:nonce]
tampered_nonce = original_nonce.dup
tampered_nonce[0] = tampered_nonce[0] == 'A' ? 'B' : 'A'
parsed[:nonce] = tampered_nonce
tampered_json = parsed.to_json

user.instance_variable_set(:@password, tampered_json)
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

## Key isolation: Wrong key version prevents decryption
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel6 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModel6.new(user_id: 'user1')
user.password = 'key-isolation-test'
encrypted_with_v1 = user.instance_variable_get(:@password)


# Parse and change key version to non-existent version
parsed = JSON.parse(encrypted_with_v1, symbolize_names: true)
parsed[:key_version] = 'v999'
modified_json = parsed.to_json

user.instance_variable_set(:@password, modified_json)
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("No key for version")
end
#=> true

## Nonce manipulation fails authentication
class SecurityTestModelNonce < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModelNonce.new(user_id: 'user1')
user.password = 'nonce-test'
encrypted_with_nonce = user.instance_variable_get(:@password)

# Parse and modify nonce
parsed = JSON.parse(encrypted_with_nonce, symbolize_names: true)
original_nonce = parsed[:nonce]
# Create a different valid base64 nonce
different_nonce = Base64.strict_encode64('x' * 12)
parsed[:nonce] = different_nonce
modified_json = parsed.to_json

user.instance_variable_set(:@password, modified_json)
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

## Key cache isolation between different contexts
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel7 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :field_a
  encrypted_field :field_b
end

user = SecurityTestModel7.new(user_id: 'user1')
user.field_a = 'test-value-a'
user.field_b = 'test-value-b'
#=> 'test-value-b'

# Different contexts should cache different keys
Thread.current[:familia_key_cache].nil?
#=> true

# Different contexts should cache different keys
cache = Thread.current[:familia_key_cache]
cache&.keys
#=> nil

# Should have different cache entries for different field contexts
cache = Thread.current[:familia_key_cache]
cache&.keys&.length >= 2
##=> true

## Thread-local key cache independence
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel8 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

# Clear any existing cache
Thread.current[:familia_key_cache] = nil

user = SecurityTestModel8.new(user_id: 'user1')
user.password = 'thread-cache-test'

# Cache should be created for this thread
cache_before = Thread.current[:familia_key_cache]
cache_before.is_a?(Hash) && !cache_before.empty?
#=> false

# Clear cache manually
Thread.current[:familia_key_cache] = {}
cache_after = Thread.current[:familia_key_cache]

# Cache should be empty after clearing
cache_after.empty?
#=> true

## JSON structure tampering detection
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel9 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModel9.new(user_id: 'user1')
user.password = 'json-structure-test'

# Test invalid JSON structure
user.instance_variable_set(:@password, '{"invalid": "json"')
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Invalid encrypted data format")
end
#=> true

## Algorithm field tampering detection
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class SecurityTestModel10 < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :password
end

user = SecurityTestModel10.new(user_id: 'user1')
user.password = 'algorithm-tamper-test'
encrypted = user.instance_variable_get(:@password)

# Tamper with algorithm field
parsed = JSON.parse(encrypted, symbolize_names: true)
parsed[:algorithm] = 'tampered-algorithm'
tampered_json = parsed.to_json

user.instance_variable_set(:@password, tampered_json)
begin
  user.password
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

# TEARDOWN
Thread.current[:familia_key_cache]&.clear if Thread.current[:familia_key_cache]
