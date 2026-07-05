# try/features/encryption/registry_algorithm_resolution_try.rb
#
# frozen_string_literal: true

# Registry.get error-message contract.
#
# `Registry.register` only stores a provider whose runtime dependency is present
# (available? == true), so `Registry.get` for an unregistered algorithm has two
# distinct causes worth telling apart:
#
#   1. A genuinely unknown algorithm (typo / never-existed)   -> "Unsupported algorithm"
#   2. A KNOWN algorithm whose provider isn't installed here   -> actionable "install the dependency"
#
# Case 2 is the common misstep when pinning `encrypted_field ..., algorithm:`
# ahead of a fleet rollout (e.g. pinning xchacha20poly1305 before rbnacl/libsodium
# is deployed). Before this refinement both cases returned the same "Unsupported
# algorithm" message, pointing an operator at a typo when the real fix is a
# missing dependency.
#
# These checks simulate a node WITHOUT the xchacha provider by removing it from
# the live registry (it stays in `known_providers`), then restore the registry so
# later tryouts see it intact. No database writes.

require_relative '../../support/helpers/test_helpers'

Familia::Encryption::Registry.setup!

## known_providers lists every provider Familia can register, independent of availability
Familia::Encryption::Registry.known_providers.map { |k| k::ALGORITHM }.sort
#=> ['aes-256-gcm', 'xchacha20poly1305']

## An available algorithm resolves to a provider instance
Familia::Encryption::Registry.get('aes-256-gcm').class
#=> Familia::Encryption::Providers::AESGCMProvider

## A genuinely unknown algorithm raises the plain "Unsupported algorithm" error
begin
  Familia::Encryption::Registry.get('totally-made-up')
  :no_raise
rescue Familia::EncryptionError => e
  e.message
end
#=> 'Unsupported algorithm: totally-made-up'

# Each check below simulates a node where the xchacha provider's dependency
# (rbnacl) is absent by removing it from the live registry for the duration of the
# call, then restoring it in an ensure. The mutate/assert/restore is kept inside a
# single test block so it can't leak into other tryouts regardless of how the
# runner orders top-level setup code. (xchacha stays in `known_providers` -- only
# the live registration is dropped, which is exactly what an absent dependency
# looks like: `register` skipped it because `available?` was false.)

## Each provider declares its own dependency (nil when always available), so the error hint is not hardcoded
[
  Familia::Encryption::Providers::AESGCMProvider.dependency_hint,
  Familia::Encryption::Providers::XChaCha20Poly1305Provider.dependency_hint,
]
#=> [nil, 'rbnacl/libsodium']

## A known-but-unavailable algorithm names the provider and sources the dependency hint from the provider itself
saved = Familia::Encryption::Registry.providers.dup
Familia::Encryption::Registry.providers.delete('xchacha20poly1305')
begin
  Familia::Encryption::Registry.get('xchacha20poly1305')
  :no_raise
rescue Familia::EncryptionError => e
  hint = Familia::Encryption::Providers::XChaCha20Poly1305Provider.dependency_hint
  [
    e.message.include?('is known but its provider'),
    e.message.include?('XChaCha20Poly1305Provider'),
    e.message.include?("requires #{hint}"), # dependency text comes from .dependency_hint, not a literal
  ]
ensure
  Familia::Encryption::Registry.providers.replace(saved)
end
#=> [true, true, true]

## The message is correct for the decrypt path too: installing the dependency covers reads and writes, and pinning is flagged as write-only
# get() runs on both encrypt and decrypt (Manager#decrypt resolves the provider from
# the stored envelope), so the guidance must not imply pinning fixes decrypt.
saved = Familia::Encryption::Registry.providers.dup
Familia::Encryption::Registry.providers.delete('xchacha20poly1305')
begin
  Familia::Encryption::Registry.get('xchacha20poly1305')
  :no_raise
rescue Familia::EncryptionError => e
  [
    e.message.include?('read or write this algorithm'),
    e.message.include?('cannot decrypt ciphertext already written'),
    e.message.downcase.include?('for writes'), # pinning scoped to writes
  ]
ensure
  Familia::Encryption::Registry.providers.replace(saved)
end
#=> [true, true, true]

## A hintless provider (always-available OpenSSL AES) omits the "requires ..." clause rather than naming another provider's library
saved = Familia::Encryption::Registry.providers.dup
Familia::Encryption::Registry.providers.delete('aes-256-gcm')
begin
  Familia::Encryption::Registry.get('aes-256-gcm')
  :no_raise
rescue Familia::EncryptionError => e
  [e.message.include?('is known but its provider'), e.message.include?('requires')]
ensure
  Familia::Encryption::Registry.providers.replace(saved)
end
#=> [true, false]

## The known-but-unavailable message does NOT reuse the misleading "Unsupported algorithm" wording
saved = Familia::Encryption::Registry.providers.dup
Familia::Encryption::Registry.providers.delete('xchacha20poly1305')
begin
  Familia::Encryption::Registry.get('xchacha20poly1305')
  :no_raise
rescue Familia::EncryptionError => e
  e.message.start_with?('Unsupported algorithm')
ensure
  Familia::Encryption::Registry.providers.replace(saved)
end
#=> false

## Restore is automatic: xchacha resolves again outside the simulated-absent block
Familia::Encryption::Registry.get('xchacha20poly1305').class
#=> Familia::Encryption::Providers::XChaCha20Poly1305Provider
