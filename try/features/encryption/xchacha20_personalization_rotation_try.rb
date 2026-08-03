# try/features/encryption/xchacha20_personalization_rotation_try.rb
#
# frozen_string_literal: true

# Locks in the backward-compatibility guarantee for BLAKE2b personalization
# rotation (issue #333), mirroring the AES-GCM HKDF salt design from #310/#311:
# the XChaCha20 personalization is driven by encryption_personalization plus a
# dedicated history knob (encryption_personalization_history), and moving off
# the built-in 'FamilialMatters' default must NOT make previously-encrypted
# data unreadable. The providers expose an ordered candidate list (current
# first, then rotation history, then the legacy default); decryption walks it
# until the authenticated decrypt succeeds.

require_relative '../../support/helpers/test_helpers'
require 'base64'

set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) }, current_version: :v1)

@orig_personal = Familia.config.encryption_personalization
@orig_history = Familia.config.encryption_personalization_history
@orig_salt = Familia.config.encryption_hkdf_salt

@mgr = Familia::Encryption::Manager.new(algorithm: 'xchacha20poly1305')
@ctx = 'PersonalizationRotationTest:secret:user1'

## The candidate list always includes the pre-#333 built-in personalization
provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
provider.personalizations.include?(Familia::Encryption::Providers::Blake2bPersonalization::LEGACY_PERSONALIZATION)
#=> true

## Encryption uses the current encryption_personalization as the first candidate
Familia.config.encryption_personalization = 'MyApp1.0'
Familia.config.encryption_personalization_history = []
Familia::Encryption::Providers::XChaCha20Poly1305Provider.new.personalizations.first
#=> 'MyApp1.0'

## The personalization is decoupled from the AES-GCM HKDF salt (#311): changing
## encryption_hkdf_salt does NOT change the personalization candidate list.
Familia.config.encryption_personalization = 'MyApp1.0'
Familia.config.encryption_personalization_history = []
Familia.config.encryption_hkdf_salt = 'SomeOtherSalt'
Familia::Encryption::Providers::XChaCha20Poly1305Provider.new.personalizations.first
#=> 'MyApp1.0'

## A personalization at exactly the 16-byte BLAKE2b limit round-trips
Familia.config.encryption_personalization = 'x' * 16
Familia.config.encryption_personalization_history = []
@mgr.decrypt(@mgr.encrypt('at limit ok', context: @ctx), context: @ctx)
#=> 'at limit ok'

## Ciphertext written before a personalization rotation still decrypts via history
Familia.config.encryption_personalization = 'MyApp1.0'
Familia.config.encryption_personalization_history = []
@blob_v1 = @mgr.encrypt('rotate me', context: @ctx)
Familia.config.encryption_personalization = 'MyApp2.0'
Familia.config.encryption_personalization_history = ['MyApp1.0']
@mgr.decrypt(@blob_v1, context: @ctx)
#=> 'rotate me'

## Round-trips under the new current personalization continue to work after rotation
@mgr.decrypt(@mgr.encrypt('fresh', context: @ctx), context: @ctx)
#=> 'fresh'

## Without the prior value in history, rotated ciphertext no longer decrypts
Familia.config.encryption_personalization = 'MyApp1.0'
Familia.config.encryption_personalization_history = []
@orphan = @mgr.encrypt('needs history', context: @ctx)
Familia.config.encryption_personalization = 'MyApp-x9'
Familia.config.encryption_personalization_history = []
begin
  @mgr.decrypt(@orphan, context: @ctx)
  'decrypted-unexpectedly'
rescue Familia::EncryptionError
  'failed-as-expected'
end
#=> 'failed-as-expected'

## Pre-#333 data (encrypted under the DEFAULT personalization) decrypts with
## zero history configured -- the legacy tail. This is the production
## Onetimesecret v0.26 story: nearly every 2.11 deployment encrypted under the
## built-in 'FamilialMatters'; rotating to a deployment-specific value must not
## orphan that data even when the operator configures no history at all.
Familia.config.encryption_personalization = 'FamilialMatters'
Familia.config.encryption_personalization_history = []
@default_blob = @mgr.encrypt('v0.26 secret', context: @ctx)
Familia.config.encryption_personalization = 'BrandNewApp'
Familia.config.encryption_personalization_history = []
@mgr.decrypt(@default_blob, context: @ctx)
#=> 'v0.26 secret'

## Legacy data crafted against the *literal* pre-#333 personalization string
## (not the constant) still decrypts -- guards against the constant's value
## drifting away from the hardcoded 'FamilialMatters' the old code shipped.
@provider = Familia::Encryption::Providers::XChaCha20Poly1305Provider.new
@master = Base64.strict_decode64(Familia.config.encryption_keys[:v1])
@literal_key = @provider.derive_key(@master, @ctx, personal: 'FamilialMatters')
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
Familia.config.encryption_personalization = 'AnotherFreshApp'
Familia.config.encryption_personalization_history = []
@mgr.decrypt(@literal_blob, context: @ctx)
#=> 'literal legacy'

## No false positive: a wrong personalization never "succeeds" into garbage --
## Poly1305 auth must fail and raise rather than return a plausible wrong string.
Familia.config.encryption_personalization = 'GoodPersonal'
Familia.config.encryption_personalization_history = []
@fp_blob = @mgr.encrypt('do not leak', context: @ctx)
Familia.config.encryption_personalization = 'WrongPersonal'
Familia.config.encryption_personalization_history = []
begin
  @mgr.decrypt(@fp_blob, context: @ctx)
  'false-positive!'
rescue Familia::EncryptionError
  'rejected'
end
#=> 'rejected'

## personalizations is current-first, deduplicated, and ends with the legacy value
Familia.config.encryption_personalization = 'Curr'
Familia.config.encryption_personalization_history = ['Curr', 'Prev', 'Prev']
Familia::Encryption::Providers::XChaCha20Poly1305Provider.new.personalizations
#=> ['Curr', 'Prev', 'FamilialMatters']

## Invalid history entries (non-String, blank, null bytes, >16 bytes) are
## filtered out of the candidate list -- each would otherwise raise mid-walk
## (EncryptionError or RbNaCl::LengthError) and abort the remaining candidates.
Familia.config.encryption_personalization = 'Curr'
Familia.config.encryption_personalization_history = [nil, 123, '', "nul\0led", 'x' * 17, 'ValidOld']
Familia::Encryption::Providers::XChaCha20Poly1305Provider.new.personalizations
#=> ['Curr', 'ValidOld', 'FamilialMatters']

## A decrypt walk configured with junk history entries still reaches the valid
## candidate that sits behind them, instead of aborting on the junk.
Familia.config.encryption_personalization = 'ValidOld'
Familia.config.encryption_personalization_history = []
@junk_blob = @mgr.encrypt('survives junk', context: @ctx)
Familia.config.encryption_personalization = 'NewerApp'
Familia.config.encryption_personalization_history = ['', "nul\0led", 'x' * 17, 'ValidOld']
@mgr.decrypt(@junk_blob, context: @ctx)
#=> 'survives junk'

## Request cache keys by personalization: two blobs needing different values
## both decrypt correctly inside one cache scope (a personalization-blind cache
## key would corrupt one).
Familia.config.encryption_personalization = 'CachePersA'
Familia.config.encryption_personalization_history = []
@cache_a = @mgr.encrypt('alpha', context: @ctx)
Familia.config.encryption_personalization = 'CachePersB'
Familia.config.encryption_personalization_history = []
@cache_b = @mgr.encrypt('beta', context: @ctx)
Familia.config.encryption_personalization = 'CachePersB'
Familia.config.encryption_personalization_history = ['CachePersA']
Familia::Encryption.with_request_cache do
  [@mgr.decrypt(@cache_b, context: @ctx), @mgr.decrypt(@cache_a, context: @ctx)]
end
#=> ['beta', 'alpha']

## Encrypt then decrypt the same value in one cache scope derives once. The
## encrypt path (personal nil, resolved to current_personalization) and the
## decrypt loop's first iteration (explicit personalizations.first) share a
## single cache entry, instead of filing the same derived key under nil and
## under the resolved value. A single cached entry proves the redundant second
## derivation is gone (mirrors the #311 salt behaviour).
Familia.config.encryption_personalization = 'CacheShared'
Familia.config.encryption_personalization_history = []
@shared_size = Familia::Encryption.with_request_cache do
  blob = @mgr.encrypt('shared', context: @ctx)
  @mgr.decrypt(blob, context: @ctx)
  Fiber[:familia_request_cache].size
end
@shared_size
#=> 1

## Fail closed: a nil encryption_personalization refuses to ENCRYPT rather than
## silently deriving under the legacy default (which would withhold the
## per-deployment domain separation). The raw attr_writer can set nil past the
## reader's guards, so the check lives at derivation time.
Familia.config.encryption_personalization = nil
Familia.config.encryption_personalization_history = []
begin
  @mgr.encrypt('should not encrypt', context: @ctx)
  'encrypted-unexpectedly'
rescue Familia::EncryptionError => e
  e.message.include?('non-empty') ? 'refused' : 'wrong-error'
end
#=> 'refused'

## An empty encryption_personalization is likewise refused for encryption
Familia.config.encryption_personalization = ''
Familia.config.encryption_personalization_history = []
begin
  @mgr.encrypt('should not encrypt', context: @ctx)
  'encrypted-unexpectedly'
rescue Familia::EncryptionError
  'refused'
end
#=> 'refused'

## Decryption stays permissive even with a blank current personalization: data
## written under a now-historical value still decrypts (old data stays readable
## even if the current config is broken), while new writes are refused above.
Familia.config.encryption_personalization = 'WritePers'
Familia.config.encryption_personalization_history = []
@written = @mgr.encrypt('readable later', context: @ctx)
Familia.config.encryption_personalization = nil
Familia.config.encryption_personalization_history = ['WritePers']
@mgr.decrypt(@written, context: @ctx)
#=> 'readable later'

# TEARDOWN
Familia.config.encryption_personalization = @orig_personal
Familia.config.encryption_personalization_history = @orig_history
Familia.config.encryption_hkdf_salt = @orig_salt
clear_test_encryption_keys
# Restore the request-cache fiber-locals to their pristine (nil) state. The
# cache tests above run with_request_cache, whose ensure leaves
# `enabled=false`; in the shared full-suite process that would otherwise leak
# into a later file asserting the untouched default is nil (request_cache_try).
Fiber[:familia_request_cache] = nil
Fiber[:familia_request_cache_enabled] = nil
