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


# TEARDOWN
Thread.current[:familia_key_cache]&.clear if Thread.current[:familia_key_cache]
