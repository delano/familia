# try/encryption/providers/xchacha20_poly1305_provider_try.rb

require_relative '../../helpers/test_helpers'
require 'base64'

## XChaCha20Poly1305 provider availability check
Familia::Encryption::Providers::XChaCha20Poly1305Provider.available?
#=> true

## XChaCha20Poly1305 provider initialization
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
[provider.algorithm, provider.nonce_size, provider.auth_tag_size]
#=> ['xchacha20poly1305', 24, 16]

## XChaCha20Poly1305 provider priority is highest
Familia::Encryption::Providers::XChaCha20Poly1305Provider.priority
#=> 100

## XChaCha20Poly1305 nonce generation produces correct size
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
nonce = provider.generate_nonce
nonce.bytesize
#=> 24

## XChaCha20Poly1305 key derivation with default personalization
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
master_key = Base64.strict_decode64(test_keys[:v1])
context = 'test-context'
derived_key = provider.derive_key(master_key, context)
derived_key.bytesize
#=> 32

## XChaCha20Poly1305 key derivation with custom personalization
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
master_key = Base64.strict_decode64(test_keys[:v1])
context = 'test-context'
derived_key1 = provider.derive_key(master_key, context, personal: 'custom1')
derived_key2 = provider.derive_key(master_key, context, personal: 'custom2')
derived_key1 != derived_key2
#=> true

## XChaCha20Poly1305 key derivation rejects null bytes in personalization
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
master_key = Base64.strict_decode64(test_keys[:v1])
context = 'test-context'
provider.derive_key(master_key, context, personal: "bad\0personal")
#=!> Familia::EncryptionError
#==> error.message.include?('null bytes')

## XChaCha20Poly1305 encryption produces expected structure
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test encryption data'
result = provider.encrypt(plaintext, key)
[result.has_key?(:nonce), result.has_key?(:ciphertext), result.has_key?(:auth_tag)]
#=> [true, true, true]

## XChaCha20Poly1305 encryption nonce is 24 bytes
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test encryption data'
result = provider.encrypt(plaintext, key)
result[:nonce].bytesize
#=> 24

## XChaCha20Poly1305 encryption auth tag is 16 bytes
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test encryption data'
result = provider.encrypt(plaintext, key)
result[:auth_tag].bytesize
#=> 16

## XChaCha20Poly1305 round-trip encryption/decryption
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'XChaCha20Poly1305 round-trip test'
encrypted = provider.encrypt(plaintext, key)
decrypted = provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], encrypted[:auth_tag])
decrypted
#=> 'XChaCha20Poly1305 round-trip test'

## XChaCha20Poly1305 encryption with AAD (Additional Authenticated Data)
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test with aad'
aad = 'additional-authenticated-data'
encrypted = provider.encrypt(plaintext, key, aad)
decrypted = provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], encrypted[:auth_tag], aad)
decrypted
#=> 'test with aad'

## XChaCha20Poly1305 AAD tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test with aad'
aad = 'original-aad'
encrypted = provider.encrypt(plaintext, key, aad)
provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], encrypted[:auth_tag], 'tampered-aad')
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## XChaCha20Poly1305 nonce tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test nonce tampering'
encrypted = provider.encrypt(plaintext, key)
tampered_nonce = 'x' * 24  # Wrong nonce
provider.decrypt(encrypted[:ciphertext], key, tampered_nonce, encrypted[:auth_tag])
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## XChaCha20Poly1305 auth tag tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test auth tag tampering'
encrypted = provider.encrypt(plaintext, key)
tampered_auth_tag = 'y' * 16  # Wrong auth tag
provider.decrypt(encrypted[:ciphertext], key, encrypted[:nonce], tampered_auth_tag)
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## XChaCha20Poly1305 ciphertext tampering fails authentication
test_keys = { v1: Base64.strict_encode64('a' * 32) }
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
key = Base64.strict_decode64(test_keys[:v1])
plaintext = 'test ciphertext tampering'
encrypted = provider.encrypt(plaintext, key)
tampered_ciphertext = encrypted[:ciphertext][0..-2] + 'X'  # Change last byte
provider.decrypt(tampered_ciphertext, key, encrypted[:nonce], encrypted[:auth_tag])
#=!> Familia::EncryptionError
#==> error.message.include?('Decryption failed')

## XChaCha20Poly1305 key validation rejects nil key
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
provider.encrypt('test', nil)
#=!> Familia::EncryptionError
#==> error.message.include?('Key cannot be nil')

## XChaCha20Poly1305 key validation requires 32-byte minimum
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
short_key = 'x' * 16  # Only 16 bytes
provider.encrypt('test', short_key)
#=!> Familia::EncryptionError
#==> error.message.include?('Key must be at least 32 bytes')

## XChaCha20Poly1305 secure_wipe clears key (best effort)
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
test_key = 'secret-key-data-to-be-wiped'
original_length = test_key.length
provider.secure_wipe(test_key)
test_key.length
#=> 0

# TEARDOWN
Fiber[:familia_key_cache]&.clear if Fiber[:familia_key_cache]
