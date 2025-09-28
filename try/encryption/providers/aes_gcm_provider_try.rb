# try/encryption/providers/aes_gcm_provider_try.rb

require_relative '../../helpers/test_helpers'
require 'base64'

## AES-GCM provider availability check (always available with OpenSSL)
Familia::Encryption::Providers::AESGCMProvider.available?
#=> true

## AES-GCM provider initialization
provider = Familia::Encryption::Providers::AESGCMProvider.new
[provider.algorithm, provider.nonce_size, provider.auth_tag_size]
#=> ['aes-256-gcm', 12, 16]

## AES-GCM provider priority is fallback
Familia::Encryption::Providers::AESGCMProvider.priority
#=> 50

## AES-GCM nonce generation produces correct size
provider = Familia::Encryption::Providers::AESGCMProvider.new
nonce = provider.generate_nonce
nonce.bytesize
#=> 12

## AES-GCM key derivation with HKDF
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
master_key = Base64.strict_decode64(test_keys[:v1])
context = 'test-context'
derived_key = provider.derive_key(master_key, context)
derived_key.bytesize
#=> 32

## AES-GCM key derivation produces different keys for different contexts
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
master_key = Base64.strict_decode64(test_keys[:v1])
derived_key1 = provider.derive_key(master_key, 'context1')
derived_key2 = provider.derive_key(master_key, 'context2')
derived_key1 != derived_key2
#=> true

## AES-GCM encryption produces expected structure
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test encryption data'
result = provider.encrypt(plaintext, key)
[result.has_key?(:nonce), result.has_key?(:ciphertext), result.has_key?(:auth_tag)]
#=> [true, true, true]

## AES-GCM encryption nonce is 12 bytes
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test encryption data'
result = provider.encrypt(plaintext, key)
result[:nonce].bytesize
#=> 12

## AES-GCM encryption auth tag is 16 bytes
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test encryption data'
result = provider.encrypt(plaintext, key)
result[:auth_tag].bytesize
#=> 16

## AES-GCM round-trip encryption/decryption
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'AES-GCM round-trip test'
encrypted = provider.encrypt(plaintext, key)
decrypted = provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], encrypted[:auth_tag])
decrypted
#=> 'AES-GCM round-trip test'

## AES-GCM encryption with AAD (Additional Authenticated Data)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test with aad'
aad = 'additional-authenticated-data'
encrypted = provider.encrypt(plaintext, key, aad)
decrypted = provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], encrypted[:auth_tag], aad)
decrypted
#=> 'test with aad'

## AES-GCM AAD tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test with aad'
aad = 'original-aad'
encrypted = provider.encrypt(plaintext, key, aad)
provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], encrypted[:auth_tag], 'tampered-aad')
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## AES-GCM nonce tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test nonce tampering'
encrypted = provider.encrypt(plaintext, key)
tampered_nonce = 'x' * 12  # Wrong nonce (12 bytes for AES-GCM)
provider.decrypt(encrypted[:ciphertext], key, tampered_nonce, encrypted[:auth_tag])
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## AES-GCM auth tag tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test auth tag tampering'
encrypted = provider.encrypt(plaintext, key)
tampered_auth_tag = 'y' * 16  # Wrong auth tag
provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], tampered_auth_tag)
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## AES-GCM ciphertext tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test ciphertext tampering'
encrypted = provider.encrypt(plaintext, key)
tampered_ciphertext = encrypted[:ciphertext][0..-2] + 'X'  # Change last byte
provider.decrypt(tampered_ciphertext, key, encrypted[:nonce], encrypted[:auth_tag])
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## AES-GCM key validation rejects nil key
provider = Familia::Encryption::Providers::AESGCMProvider.new
provider.encrypt('test', nil)
#=!> Familia::EncryptionError
#==> error.message.include?('Key cannot be nil')

## AES-GCM key validation requires 32-byte minimum
provider = Familia::Encryption::Providers::AESGCMProvider.new
short_key = 'x' * 16  # Only 16 bytes
provider.encrypt('test', short_key)
#=!> Familia::EncryptionError
#==> error.message.include?('Key must be at least 32 bytes')

## AES-GCM secure_wipe clears key (best effort)
provider = Familia::Encryption::Providers::AESGCMProvider.new
test_key = 'secret-key-data-to-be-wiped'
original_length = test_key.length
provider.secure_wipe(test_key)
test_key.length
#=> 0

## AES-GCM derive_key method signature (no personal parameter)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
master_key = Base64.strict_decode64(test_keys[:v1])
context = 'signature-test'
# AES-GCM derive_key only takes master_key and context (no personal parameter)
derived_key = provider.derive_key(master_key, context)
derived_key.bytesize
#=> 32

## AES-GCM HKDF salt consistency
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::AESGCMProvider.new
master_key = Base64.strict_decode64(test_keys[:v1])
context = 'salt-test'
# Multiple derivations with same inputs should produce same key
derived_key1 = provider.derive_key(master_key, context)
derived_key2 = provider.derive_key(master_key, context)
derived_key1 == derived_key2
#=> true

# TEARDOWN
Fiber[:familia_key_cache]&.clear if Fiber[:familia_key_cache]
