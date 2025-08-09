# try/encryption/debug2_try.rb

# - Tests configuration persistence between test sections
# - Validates that config can be set and accessed in tryouts

require 'base64'

require_relative '../helpers/test_helpers'
require 'familia/encryption/providers/xchacha20_poly1305_provider'

# SETUP
Familia.config.encryption_keys = {
  v1: Base64.strict_encode64('a' * 32)
}
Familia.config.current_key_version = :v1

## Check config in test
keys = Familia.config.encryption_keys
version = Familia.config.current_key_version
[keys.nil?, version.nil?]
#=> [false, false]

## Try basic encryption in test
Familia.config.encryption_keys = {v1: Base64.strict_encode64('a' * 32)}
Familia.config.current_key_version = :v1
result = Familia::Encryption.encrypt('test', context: 'test')
result.nil?
#=> false

## XChaCha20Poly1305Provider is available when RbNaCl is loaded
@provider_class = Familia::Encryption::Providers::XChaCha20Poly1305Provider
@provider_class.available?
#=> true

## Provider has highest priority
@provider_class.priority
#=> 100

## derive_key generates 32-byte key from master key and context
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
derived_key = provider.derive_key(master_key, context)
derived_key.bytesize
#=> 32

## derive_key with same inputs produces same output
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
key1 = provider.derive_key(master_key, context)
key2 = provider.derive_key(master_key, context)
key1 == key2
#=> true

## derive_key with different contexts produces different keys
provider = @provider_class.new
master_key = 'a' * 32
context1 = 'TestModel:field:user123'
context2 = 'TestModel:field:user456'
key1 = provider.derive_key(master_key, context1)
key2 =
 provider.derive_key(master_key, context2)
key1 != key2
#=> true

## derive_key with custom personalization works
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
personal = 'custom_app_v2'
derived_key = provider.derive_key(master_key, context, personal: personal)
derived_key.bytesize
#=> 32

## derive_key rejects personalization string with null bytes
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
personal_with_null = "app\0version"
begin
  provider.derive_key(master_key, context, personal: personal_with_null)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message
end
#=> "Personalization string must not contain null bytes"

## derive_key rejects config personalization with null bytes
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
# Set config with null byte
original_personal = Familia.config.encryption_personalization
Familia.config.encryption_personalization = "bad\0config"
begin
  provider.derive_key(master_key, context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message
ensure
  Familia.config.encryption_personalization = original_personal
end
#=> "Personalization string must not contain null bytes"

## derive_key validates master key length
provider = @provider_class.new
short_key = 'a' * 16  # Too short
context = 'TestModel:field:user123'
begin
  provider.derive_key(short_key, context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message
end
#=> "Key must be at least 32 bytes"

## derive_key rejects nil master key
provider = @provider_class.new
context = 'TestModel:field:user123'
begin
  provider.derive_key(nil, context)
  "should_not_reach_here"
rescue Familia::EncryptionError => e
  e.message
end
#=> "Key cannot be nil"

## encrypt/decrypt round trip with derived key works
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
derived_key = provider.derive_key(master_key, context)
plaintext = 'sensitive data'
encrypted_data = provider.encrypt(plaintext, derived_key)
decrypted = provider.decrypt(
  encrypted_data[:ciphertext],
  derived_key,
  encrypted_data[:nonce],
  encrypted_data[:auth_tag]
)
decrypted
#=> "sensitive data"

## encrypt with additional data and derived key
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
derived_key = provider.derive_key(master_key, context)
plaintext = 'sensitive data'
additional_data = 'user_id:123'
encrypted_data = provider.encrypt(plaintext, derived_key, additional_data)
decrypted = provider.decrypt(
  encrypted_data[:ciphertext],
  derived_key,
  encrypted_data[:nonce],
  encrypted_data[:auth_tag],
  additional_data
)
decrypted
#=> "sensitive data"

## generate_nonce produces correct size
provider = @provider_class.new
nonce = provider.generate_nonce
nonce.bytesize
#=> 24

## generate_nonce produces unique values
provider = @provider_class.new
nonce1 = provider.generate_nonce
nonce2 = provider.generate_nonce
nonce1 != nonce2
#=> true

## secure_wipe works with valid key
provider = @provider_class.new
key = 'a' * 32
provider.secure_wipe(key)
# Should not raise error
true
#=> true

## secure_wipe handles nil key gracefully
provider = @provider_class.new
provider.secure_wipe(nil)
# Should not raise error
true
#=> true

# TEARDOWN
Thread.current[:familia_key_cache]&.clear if Thread.current[:familia_key_cache]
