# try/features/encryption/aes_gcm_salt_rotation_try.rb
#
# frozen_string_literal: true

# Locks in the S2 backward-compatibility guarantee (issue #310): moving the
# AES-GCM HKDF salt off the static 'FamiliaEncryption' literal to the
# application personalization must NOT make previously-encrypted data
# unreadable. The provider exposes an ordered salt list (current first, then
# rotation history, then the legacy static salt); decryption walks it until the
# authenticated decrypt succeeds.

require_relative '../../support/helpers/test_helpers'
require 'base64'

Familia.config.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.current_key_version = :v1

@orig_personal = Familia.config.encryption_personalization
@orig_history = Familia.config.encryption_personalization_history

@mgr = Familia::Encryption::Manager.new(algorithm: 'aes-256-gcm')
@ctx = 'SaltRotationTest:secret:user1'

## The AES-GCM salt list always includes the pre-#310 legacy static salt
provider = Familia::Encryption::Providers::AESGCMProvider.new
provider.hkdf_salts.include?(Familia::Encryption::Providers::AESGCMProvider::LEGACY_HKDF_SALT)
#=> true

## Encryption uses the current personalization as the first (current) salt
Familia.config.encryption_personalization = 'App-v1'
Familia.config.encryption_personalization_history = []
Familia::Encryption::Providers::AESGCMProvider.new.hkdf_salts.first
#=> 'App-v1'

## Ciphertext written before a personalization rotation still decrypts via history
Familia.config.encryption_personalization = 'App-v1'
Familia.config.encryption_personalization_history = []
@blob_v1 = @mgr.encrypt('rotate me', context: @ctx)
Familia.config.encryption_personalization = 'App-v2'
Familia.config.encryption_personalization_history = ['App-v1']
@mgr.decrypt(@blob_v1, context: @ctx)
#=> 'rotate me'

## Round-trips under the new current salt continue to work after rotation
@mgr.decrypt(@mgr.encrypt('fresh', context: @ctx), context: @ctx)
#=> 'fresh'

## Without the prior value in history, rotated ciphertext no longer decrypts
Familia.config.encryption_personalization = 'App-v1'
Familia.config.encryption_personalization_history = []
@orphan = @mgr.encrypt('needs history', context: @ctx)
Familia.config.encryption_personalization = 'App-x9'
Familia.config.encryption_personalization_history = []
begin
  @mgr.decrypt(@orphan, context: @ctx)
  'decrypted-unexpectedly'
rescue Familia::EncryptionError
  'failed-as-expected'
end
#=> 'failed-as-expected'

## Pre-#310 data (encrypted under the legacy static salt) decrypts with zero config
# Craft ciphertext exactly as the old code did: derive with the legacy salt.
@provider = Familia::Encryption::Providers::AESGCMProvider.new
@master = Base64.strict_decode64(Familia.config.encryption_keys[:v1])
@legacy_key = @provider.derive_key(@master, @ctx, salt: Familia::Encryption::Providers::AESGCMProvider::LEGACY_HKDF_SALT)
@enc = @provider.encrypt('legacy secret', @legacy_key)
@legacy_blob = Familia::JsonSerializer.dump(
  Familia::Encryption::EncryptedData.new(
    algorithm: @provider.algorithm,
    nonce: Base64.strict_encode64(@enc[:nonce]),
    ciphertext: Base64.strict_encode64(@enc[:ciphertext]),
    auth_tag: Base64.strict_encode64(@enc[:auth_tag]),
    key_version: :v1,
    encoding: 'UTF-8'
  ).to_h
)
# A brand-new deployment with a custom personalization and no history at all:
Familia.config.encryption_personalization = 'BrandNewApp'
Familia.config.encryption_personalization_history = []
@mgr.decrypt(@legacy_blob, context: @ctx)
#=> 'legacy secret'

# TEARDOWN
Familia.config.encryption_personalization = @orig_personal
Familia.config.encryption_personalization_history = @orig_history
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
