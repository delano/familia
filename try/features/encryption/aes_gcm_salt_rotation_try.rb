# try/features/encryption/aes_gcm_salt_rotation_try.rb
#
# frozen_string_literal: true

# Locks in the S2 backward-compatibility guarantee (issue #310) together with the
# #311 decoupling: the AES-GCM HKDF salt is driven by a dedicated config knob
# (encryption_hkdf_salt), SEPARATE from the XChaCha20 personalization, and moving
# off the static 'FamiliaEncryption' literal must NOT make previously-encrypted
# data unreadable. The provider exposes an ordered salt list (current first, then
# rotation history, then the legacy static salt); decryption walks it until the
# authenticated decrypt succeeds.

require_relative '../../support/helpers/test_helpers'
require 'base64'

Familia.config.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.current_key_version = :v1

@orig_salt = Familia.config.encryption_hkdf_salt
@orig_history = Familia.config.encryption_hkdf_salt_history
@orig_personal = Familia.config.encryption_personalization

@mgr = Familia::Encryption::Manager.new(algorithm: 'aes-256-gcm')
@ctx = 'SaltRotationTest:secret:user1'

## The AES-GCM salt list always includes the pre-#310 legacy static salt
provider = Familia::Encryption::Providers::AESGCMProvider.new
provider.hkdf_salts.include?(Familia::Encryption::Providers::AESGCMProvider::LEGACY_HKDF_SALT)
#=> true

## Encryption uses the current encryption_hkdf_salt as the first (current) salt
Familia.config.encryption_hkdf_salt = 'App-v1'
Familia.config.encryption_hkdf_salt_history = []
Familia::Encryption::Providers::AESGCMProvider.new.hkdf_salts.first
#=> 'App-v1'

## The AES-GCM salt is decoupled from the XChaCha20 personalization (#311):
## changing the personalization does NOT change the AES-GCM salt list.
Familia.config.encryption_hkdf_salt = 'App-v1'
Familia.config.encryption_hkdf_salt_history = []
Familia.config.encryption_personalization = 'Other'
Familia::Encryption::Providers::AESGCMProvider.new.hkdf_salts.first
#=> 'App-v1'

## The HKDF salt carries no 16-byte BLAKE2b limit -- a long salt round-trips (#311)
@long_salt = 'a-very-long-application-specific-hkdf-salt-well-over-16-bytes'
Familia.config.encryption_hkdf_salt = @long_salt
Familia.config.encryption_hkdf_salt_history = []
@mgr.decrypt(@mgr.encrypt('long salt ok', context: @ctx), context: @ctx)
#=> 'long salt ok'

## Ciphertext written before a salt rotation still decrypts via history
Familia.config.encryption_hkdf_salt = 'App-v1'
Familia.config.encryption_hkdf_salt_history = []
@blob_v1 = @mgr.encrypt('rotate me', context: @ctx)
Familia.config.encryption_hkdf_salt = 'App-v2'
Familia.config.encryption_hkdf_salt_history = ['App-v1']
@mgr.decrypt(@blob_v1, context: @ctx)
#=> 'rotate me'

## Round-trips under the new current salt continue to work after rotation
@mgr.decrypt(@mgr.encrypt('fresh', context: @ctx), context: @ctx)
#=> 'fresh'

## Without the prior value in history, rotated ciphertext no longer decrypts
Familia.config.encryption_hkdf_salt = 'App-v1'
Familia.config.encryption_hkdf_salt_history = []
@orphan = @mgr.encrypt('needs history', context: @ctx)
Familia.config.encryption_hkdf_salt = 'App-x9'
Familia.config.encryption_hkdf_salt_history = []
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
# A brand-new deployment with a custom salt and no history at all:
Familia.config.encryption_hkdf_salt = 'BrandNewApp'
Familia.config.encryption_hkdf_salt_history = []
@mgr.decrypt(@legacy_blob, context: @ctx)
#=> 'legacy secret'

## Legacy data crafted against the *literal* pre-#310 salt string (not the
## constant) still decrypts -- guards against the constant's value drifting away
## from the hardcoded 'FamiliaEncryption' the old code shipped.
@literal_key = @provider.derive_key(@master, @ctx, salt: 'FamiliaEncryption')
@literal_enc = @provider.encrypt('literal legacy', @literal_key)
@literal_blob = Familia::JsonSerializer.dump(
  Familia::Encryption::EncryptedData.new(
    algorithm: @provider.algorithm,
    nonce: Base64.strict_encode64(@literal_enc[:nonce]),
    ciphertext: Base64.strict_encode64(@literal_enc[:ciphertext]),
    auth_tag: Base64.strict_encode64(@literal_enc[:auth_tag]),
    key_version: :v1,
    encoding: 'UTF-8'
  ).to_h
)
Familia.config.encryption_hkdf_salt = 'AnotherFreshApp'
Familia.config.encryption_hkdf_salt_history = []
@mgr.decrypt(@literal_blob, context: @ctx)
#=> 'literal legacy'

## No false positive: a wrong salt never "succeeds" into garbage -- GCM auth must
## fail and raise rather than return a plausible-looking wrong string.
Familia.config.encryption_hkdf_salt = 'GoodSalt'
Familia.config.encryption_hkdf_salt_history = []
@fp_blob = @mgr.encrypt('do not leak', context: @ctx)
Familia.config.encryption_hkdf_salt = 'WrongSalt'
Familia.config.encryption_hkdf_salt_history = []
begin
  @mgr.decrypt(@fp_blob, context: @ctx)
  'false-positive!'
rescue Familia::EncryptionError
  'rejected'
end
#=> 'rejected'

## hkdf_salts is current-first, deduplicated, and ends with the legacy salt
Familia.config.encryption_hkdf_salt = 'Curr'
Familia.config.encryption_hkdf_salt_history = ['Curr', 'Prev', 'Prev']
Familia::Encryption::Providers::AESGCMProvider.new.hkdf_salts
#=> ['Curr', 'Prev', 'FamiliaEncryption']

## Request cache keys by salt: two blobs needing different salts both decrypt
## correctly inside one cache scope (a salt-blind cache key would corrupt one).
Familia.config.encryption_hkdf_salt = 'CacheA'
Familia.config.encryption_hkdf_salt_history = []
@cache_a = @mgr.encrypt('alpha', context: @ctx)
Familia.config.encryption_hkdf_salt = 'CacheB'
Familia.config.encryption_hkdf_salt_history = []
@cache_b = @mgr.encrypt('beta', context: @ctx)
Familia.config.encryption_hkdf_salt = 'CacheB'
Familia.config.encryption_hkdf_salt_history = ['CacheA']
Familia::Encryption.with_request_cache do
  [@mgr.decrypt(@cache_b, context: @ctx), @mgr.decrypt(@cache_a, context: @ctx)]
end
#=> ['beta', 'alpha']

## Issue 2 (#311): encrypt then decrypt the same value in one cache scope derives
## once. The encrypt path (salt nil, resolved to hkdf_salts.first) and the decrypt
## loop's first iteration (explicit hkdf_salts.first) now share a single cache
## entry, instead of filing the same derived key under nil and under the resolved
## salt. A single cached entry proves the redundant second derivation is gone.
Familia.config.encryption_hkdf_salt = 'CacheShared'
Familia.config.encryption_hkdf_salt_history = []
@shared_size = Familia::Encryption.with_request_cache do
  blob = @mgr.encrypt('shared', context: @ctx)
  @mgr.decrypt(blob, context: @ctx)
  Fiber[:familia_request_cache].size
end
@shared_size
#=> 1

# TEARDOWN
Familia.config.encryption_hkdf_salt = @orig_salt
Familia.config.encryption_hkdf_salt_history = @orig_history
Familia.config.encryption_personalization = @orig_personal
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
# Restore the request-cache fiber-locals to their pristine (nil) state. The
# cache tests above run with_request_cache, whose ensure leaves
# `enabled=false`; in the shared full-suite process that would otherwise leak
# into a later file asserting the untouched default is nil (request_cache_try).
Fiber[:familia_request_cache] = nil
Fiber[:familia_request_cache_enabled] = nil
