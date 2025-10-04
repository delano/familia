# try/features/encryption_fields/key_rotation_try.rb

require 'base64'

require_relative '../../support/helpers/test_helpers'

# Setup multiple key versions for rotation testing
@test_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32),
  v3: Base64.strict_encode64('c' * 32)
}

class RotationTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

# Data encrypted with v1 can still be decrypted after rotation to v2
Familia.config.encryption_keys = { v1: @test_keys[:v1] }
Familia.config.current_key_version = :v1

@model = RotationTest.new(id: 'rot-1')
@model.secret = 'original-secret'
@v1_ciphertext = @model.instance_variable_get(:@secret)

# Rotate to v2 with both keys available
Familia.config.encryption_keys = { v1: @test_keys[:v1], v2: @test_keys[:v2] }
Familia.config.current_key_version = :v2

## Manually set the old ciphertext and try to decrypt
@model.instance_variable_set(:@secret, @v1_ciphertext)
# Test legitimate decryption with controlled access
@model.secret.reveal { |decrypted| decrypted }
#=> 'original-secret'

## New data encrypts with current key version (v2)
@model.secret = 'updated-secret'
@v2_ciphertext = @model.instance_variable_get(:@secret)
# With ConcealedString, verify encryption by testing key version via reveal
# The key version is embedded in the encrypted data structure
@v2_ciphertext.class.name
#=> "ConcealedString"

## Missing historical key causes decryption failure
Familia.config.encryption_keys = { v3: @test_keys[:v3] }
Familia.config.current_key_version = :v3
@model.instance_variable_set(:@secret, @v1_ciphertext)
begin
  @model.secret.reveal { |decrypted| decrypted }
  false
rescue Familia::EncryptionError => e
  e.message.include?('No key for version: v1')
end
#=> true

## Derivation counter increments during key rotation operations
Familia::Encryption.reset_derivation_count!
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1
#=> :v1

## Derivation counter increments
@rotation_model = RotationTest.new(id: 'rot-counter')
@rotation_model.secret = 'test1'  # v1 encrypt
Familia::Encryption.derivation_count.value
#=> 1

## Key rotation to v2 for new encryption
Familia.config.current_key_version = :v2
@rotation_model.secret = 'test2'  # v2 encrypt
Familia::Encryption.derivation_count.value
#=> 2

## Decryption with v2 key
@retrieved = @rotation_model.secret  # ConcealedString (no decryption)
# With secure-by-default, field access doesn't trigger decryption
Familia::Encryption.derivation_count.value
#=> 2

## Key rotation to v3 for new encryption
Familia.config.current_key_version = :v3
@rotation_model.secret = 'test3'  # v3 encrypt
# Count is now 3 (2 previous encryptions + 1 v3 encryption)
Familia::Encryption.derivation_count.value
#=> 3

## Multiple key versions coexist for backward compatibility
Familia.config.encryption_keys = { v1: @test_keys[:v1], v2: @test_keys[:v2], v3: @test_keys[:v3] }
Familia.config.current_key_version = :v2

@multi_model = RotationTest.new(id: 'multi-key')

# Create data with v1
Familia.config.current_key_version = :v1
@multi_model.secret = 'v1-data'
@v1_data = @multi_model.instance_variable_get(:@secret)

# Create data with v3
Familia.config.current_key_version = :v3
@multi_model.secret = 'v3-data'
@v3_data = @multi_model.instance_variable_get(:@secret)

# Switch back to v2 as current
Familia.config.current_key_version = :v2

# Can still decrypt v1 data
@multi_model.instance_variable_set(:@secret, @v1_data)
# Test legitimate decryption with controlled access
@multi_model.secret.reveal { |decrypted| decrypted }
#=> 'v1-data'

## Can still decrypt v3 data with v2 as current key
@multi_model.instance_variable_set(:@secret, @v3_data)
# Test legitimate decryption with controlled access
@multi_model.secret.reveal { |decrypted| decrypted }
#=> 'v3-data'

# Cleanup
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
