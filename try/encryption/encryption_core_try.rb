# try/encryption/encryption_core_try.rb

require_relative '../helpers/test_helpers'
require_relative '../../lib/familia/encryption'
require 'base64'

# Test constants will be redefined in each test since variables don't persist

## Basic round-trip encryption and decryption works
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "sensitive data here"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
decrypted = Familia::Encryption.decrypt(encrypted, context: context)
decrypted
#=> "sensitive data here"

## Encrypted data contains expected JSON structure
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "sensitive data here"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
encrypted_data = JSON.parse(encrypted, symbolize_names: true)
encrypted_data[:algorithm]
#=> "aes-256-gcm"

## Encrypted data includes current key version
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "sensitive data here"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2
encrypted = Familia::Encryption.encrypt(plaintext, context: context)
encrypted_data = JSON.parse(encrypted, symbolize_names: true)
encrypted_data[:key_version]
#=> "v2"## Nonce is unique - same plaintext encrypts to different ciphertext
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "sensitive data here"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2
encrypted1 = Familia::Encryption.encrypt(plaintext, context: context)
encrypted2 = Familia::Encryption.encrypt(plaintext, context: context)
encrypted1 != encrypted2
#=> true

## But both decrypt to same plaintext
test_keys = { v1: Base64.strict_encode64('a' * 32), v2: Base64.strict_encode64('b' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "sensitive data here"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v2
encrypted1 = Familia::Encryption.encrypt(plaintext, context: context)
encrypted2 = Familia::Encryption.encrypt(plaintext, context: context)
decrypted1 = Familia::Encryption.decrypt(encrypted1, context: context)
decrypted2 = Familia::Encryption.decrypt(encrypted2, context: context)
[decrypted1, decrypted2]
#=> ["sensitive data here", "sensitive data here"]

## Nil plaintext returns nil
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
Familia::Encryption.encrypt(nil, context: 'test')
#=> nil

## Empty string plaintext returns nil
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
Familia::Encryption.encrypt("", context: 'test')
#=> nil

## AAD prevents decryption with wrong additional data - raises EncryptionError
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"
plaintext = "sensitive data here"
additional_data = "user123:email@example.com"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt(plaintext, context: context, additional_data: additional_data)

begin
  Familia::Encryption.decrypt(encrypted, context: context, additional_data: "wrong_aad")
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true


## Unknown algorithm raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Create encrypted data with unknown algorithm. Error should not leak algorithm details.
invalid_encrypted = {
  algorithm: "unknown-cipher",
  key_version: "v1",
  nonce: Base64.strict_encode64("x" * 12),
  ciphertext: Base64.strict_encode64("encrypted_data"),
  auth_tag: Base64.strict_encode64("y" * 16)
}.to_json

Familia::Encryption.decrypt(invalid_encrypted, context: context)
#=!> Familia::EncryptionError
#==> error.message.include?("Decryption failed")
#==> error.message.include?("unknown-cipher")

## Malformed JSON raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

Familia::Encryption.decrypt("invalid json {", context: context)
#=!> Familia::EncryptionError
#==> error.message.include?("Decryption failed")

## Invalid base64 nonce raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Create encrypted data with invalid base64 nonce
invalid_encrypted = {
  algorithm: "aes-256-gcm",
  key_version: "v1",
  nonce: "invalid_base64!@#",
  ciphertext: Base64.strict_encode64("encrypted_data"),
  auth_tag: Base64.strict_encode64("y" * 16)
}.to_json

begin
  Familia::Encryption.decrypt(invalid_encrypted, context: context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

## Invalid base64 auth_tag raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Create encrypted data with invalid base64 auth_tag
invalid_encrypted = {
  algorithm: "aes-256-gcm",
  key_version: "v1",
  nonce: Base64.strict_encode64("x" * 12),
  ciphertext: Base64.strict_encode64("encrypted_data"),
  auth_tag: "invalid_base64!@#"
}.to_json

begin
  Familia::Encryption.decrypt(invalid_encrypted, context: context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

## Wrong nonce size raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Create encrypted data with wrong nonce size (8 bytes instead of 12)
invalid_encrypted = {
  algorithm: "aes-256-gcm",
  key_version: "v1",
  nonce: Base64.strict_encode64("x" * 8),
  ciphertext: Base64.strict_encode64("encrypted_data"),
  auth_tag: Base64.strict_encode64("y" * 16)
}.to_json

begin
  Familia::Encryption.decrypt(invalid_encrypted, context: context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Invalid encrypted data")
end
#=> true

## Wrong auth_tag size raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Create encrypted data with wrong auth_tag size (8 bytes instead of 16)
invalid_encrypted = {
  algorithm: "aes-256-gcm",
  key_version: "v1",
  nonce: Base64.strict_encode64("x" * 12),
  ciphertext: Base64.strict_encode64("encrypted_data"),
  auth_tag: Base64.strict_encode64("y" * 8)
}.to_json

begin
  Familia::Encryption.decrypt(invalid_encrypted, context: context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Invalid encrypted data")
end
#=> true

## Missing required fields raises sanitized error
test_keys = { v1: Base64.strict_encode64('a' * 32) }
context = "TestModel:secret_field:user123"

Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Create encrypted data missing nonce field
invalid_encrypted = {
  algorithm: "aes-256-gcm",
  key_version: "v1",
  ciphertext: Base64.strict_encode64("encrypted_data"),
  auth_tag: Base64.strict_encode64("y" * 16)
}.to_json

begin
  Familia::Encryption.decrypt(invalid_encrypted, context: context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message.include?("Decryption failed")
end
#=> true

# TEARDOWN
Thread.current[:familia_key_cache]&.clear if Thread.current[:familia_key_cache]
