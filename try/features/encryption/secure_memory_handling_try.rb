# try/features/encryption/secure_memory_handling_try.rb
#
# frozen_string_literal: true

# try/encryption/secure_memory_handling_try.rb

require_relative '../../support/helpers/test_helpers'
require_relative '../../../lib/familia/encryption/providers/secure_xchacha20_poly1305_provider'
require 'base64'

# SETUP
set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) },
                         current_version: :v1)

## SecureXChaCha20Poly1305Provider is available when dependencies are loaded
@provider_class = Familia::Encryption::Providers::SecureXChaCha20Poly1305Provider
@provider_class.available?
#=> true

## Provider has higher priority than regular XChaCha20Poly1305Provider
@provider_class.priority > Familia::Encryption::Providers::XChaCha20Poly1305Provider.priority
#=> true

## secure_wipe clears key data from memory
provider = @provider_class.new
key = 'sensitive_key_data_here_' * 2  # 50 bytes
original_key = key.dup
provider.secure_wipe(key)
key.empty?
#=> true

## secure_wipe handles nil keys gracefully
provider = @provider_class.new
provider.secure_wipe(nil)
# Should not raise error
true
#=> true

## derive_key clears intermediate personalization data
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'

# Create a test to verify personalization string gets cleared
# (We can't directly test this but we verify the function works)
derived_key = provider.derive_key(master_key, context, personal: 'test_personal')
derived_key.bytesize
#=> 32

## derive_key leaves the caller's context string encoding untouched (#356)
provider = @provider_class.new
context = (+'TestModel:field:user123').force_encoding(Encoding::UTF_8)
provider.derive_key('a' * 32, context)
context.encoding
#=> Encoding::UTF_8

## derive_key accepts a frozen context string without raising (#356)
provider = @provider_class.new
provider.derive_key('a' * 32, 'TestModel:field:user123'.freeze).bytesize
#=> 32

## derive_key tolerates non-String contexts (#356)
provider = @provider_class.new
provider.derive_key('a' * 32, :symbol_context).bytesize
#=> 32

## derive_key output is unchanged by the no-mutation fix: still matches the
## sibling provider byte for byte, so existing ciphertexts stay decryptable
provider = @provider_class.new
sibling = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
context = 'TestModel:field:user123'
provider.derive_key('a' * 32, context) == sibling.derive_key('a' * 32, context)
#=> true

## Secure provider shares the personalization rotation list with its sibling
## via Blake2bPersonalization: current first, then history, then the legacy
## tail -- and byte-identical to the registered provider's list (#333). The two
## files have drifted apart before (#250, #356), so identity matters, not just
## shape.
provider = @provider_class.new
sibling = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
@op = Familia.config.encryption_personalization
@oh = Familia.config.encryption_personalization_history
Familia.config.encryption_personalization = 'SecureTry'
Familia.config.encryption_personalization_history = ['SecureOldTry']
@rotation = [provider.personalizations, provider.personalizations == sibling.personalizations]
Familia.config.encryption_personalization = @op
Familia.config.encryption_personalization_history = @oh
@rotation
#=> [['SecureTry', 'SecureOldTry', 'FamilialMatters'], true]

## Secure provider current_personalization returns the configured write-path value (#333)
provider = @provider_class.new
@op = Familia.config.encryption_personalization
Familia.config.encryption_personalization = 'SecureCurrent'
@current = provider.current_personalization
Familia.config.encryption_personalization = @op
@current
#=> 'SecureCurrent'

## Secure provider current_personalization fails closed on a nil config,
## exactly like the sibling provider (#333)
provider = @provider_class.new
@op = Familia.config.encryption_personalization
Familia.config.encryption_personalization = nil
@refusal = begin
  provider.current_personalization
  'no-error'
rescue Familia::EncryptionError => e
  e.message.include?('non-empty') ? 'refused' : 'other-error'
end
Familia.config.encryption_personalization = @op
@refusal
#=> 'refused'

## Secure provider derive_key rejects a >16-byte personalization with a clean
## EncryptionError instead of RbNaCl::LengthError (#333)
provider = @provider_class.new
provider.derive_key('a' * 32, 'TestModel:field:user123', personal: 'x' * 17)
#=!> Familia::EncryptionError
#==> error.message.include?('16 bytes')

## encrypt operation clears key after use (demonstration)
provider = @provider_class.new
master_key = ('a' * 32).dup  # Make mutable copy
derived_key = provider.derive_key(master_key, 'test_context')
plaintext = 'sensitive data'

# Key will be cleared after encryption
encrypted_data = provider.encrypt(plaintext, derived_key)
encrypted_data.key?(:ciphertext) && encrypted_data.key?(:nonce) && encrypted_data.key?(:auth_tag)
#=> true

## decrypt operation clears key after use (demonstration)
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
derived_key = provider.derive_key(master_key, context)
plaintext = 'sensitive data'

# Encrypt first
encrypted_data = provider.encrypt(plaintext, derived_key.dup)

# Create fresh key for decryption (since original was cleared)
fresh_key = provider.derive_key(master_key, context)
decrypted = provider.decrypt(
  encrypted_data[:ciphertext],
  fresh_key,
  encrypted_data[:nonce],
  encrypted_data[:auth_tag]
)
decrypted
#=> "sensitive data"

## Key derivation with null byte validation still works
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

## Round-trip encryption/decryption works with secure provider
provider = @provider_class.new
master_key = 'a' * 32
context = 'TestModel:field:user123'
plaintext = 'sensitive data here'

# Derive keys separately since they get cleared after use
key_for_encrypt = provider.derive_key(master_key, context)
key_for_decrypt = provider.derive_key(master_key, context)

encrypted_data = provider.encrypt(plaintext, key_for_encrypt)
decrypted = provider.decrypt(
  encrypted_data[:ciphertext],
  key_for_decrypt,
  encrypted_data[:nonce],
  encrypted_data[:auth_tag]
)
decrypted
#=> "sensitive data here"

## Generate nonce produces correct size
provider = @provider_class.new
nonce = provider.generate_nonce
nonce.bytesize
#=> 24

## Provider algorithm identifier distinguishes it from regular provider
@provider_class.const_get(:ALGORITHM)
#=> "xchacha20poly1305-secure"

# TEARDOWN
clear_test_encryption_keys
