# try/features/encryption/roundtrip_validation_try.rb
#
# frozen_string_literal: true

# try/encryption/debug4_try.rb

# - Tests full encryption/decryption round trips
# - Validates that encrypted data can be successfully decrypted

require 'base64'

require_relative '../../support/helpers/test_helpers'

## Test successful encryption
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
result = Familia::Encryption.encrypt('test', context: 'test')
result.class == String && result.length > 0
#=> true

## Test successful decryption
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
encrypted = Familia::Encryption.encrypt('test', context: 'test')
decrypted = Familia::Encryption.decrypt(encrypted, context: 'test')
decrypted
#=> 'test'


# TEARDOWN
