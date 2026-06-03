# try/features/encryption/request_cache_try.rb
#
# frozen_string_literal: true

# Locks in the opt-in request-scoped key cache:
# Familia::Encryption.with_request_cache memoises derived keys per
# fiber for the duration of the block, and clears/​wipes them on exit.
# Outside the block, derivation is never cached (secure by default).
# The cache lookup lives in Manager#derive_key_without_increment so it
# covers both encrypt and decrypt.

require_relative '../../support/helpers/test_helpers'
require 'base64'

Familia.config.encryption_keys = {
  v1: Base64.strict_encode64('a' * 32),
  v2: Base64.strict_encode64('b' * 32),
}
Familia.config.current_key_version = :v1

@mgr = Familia::Encryption::Manager.new
@ctx = 'RequestCacheTest:secret:user1'

## By default (no block) the request cache is inert
Fiber[:familia_request_cache_enabled]
#=> nil

## A derivation outside the block does not populate any fiber cache
@mgr.encrypt('alpha', context: @ctx)
Fiber[:familia_request_cache]
#=> nil

## Inside with_request_cache the fiber cache is an active Hash
@inside = Familia::Encryption.with_request_cache do
  @mgr.encrypt('beta', context: @ctx)
  Fiber[:familia_request_cache].dup
end
[@inside.is_a?(Hash), @inside.size.positive?]
#=> [true, true]

## Repeated derivations for the same algorithm/version/context reuse one entry
@sizes = Familia::Encryption.with_request_cache do
  @mgr.encrypt('one', context: @ctx)
  @mgr.encrypt('two', context: @ctx)
  @mgr.encrypt('three', context: @ctx)
  Fiber[:familia_request_cache].size
end
@sizes
#=> 1

## A different context derives (and caches) a separate key
@multi = Familia::Encryption.with_request_cache do
  @mgr.encrypt('x', context: 'RequestCacheTest:secret:userA')
  @mgr.encrypt('y', context: 'RequestCacheTest:secret:userB')
  Fiber[:familia_request_cache].size
end
@multi
#=> 2

## Caching does not corrupt round-trips (encrypt + decrypt inside the block)
@roundtrip = Familia::Encryption.with_request_cache do
  blob = @mgr.encrypt('top secret', context: @ctx)
  @mgr.decrypt(blob, context: @ctx)
end
@roundtrip
#=> 'top secret'

## A cached key still decrypts data that was encrypted before the block
@pre_blob = @mgr.encrypt('persisted', context: @ctx)
@after = Familia::Encryption.with_request_cache do
  @mgr.decrypt(@pre_blob, context: @ctx)
end
@after
#=> 'persisted'

## The block wipes and disables the cache on exit
Familia::Encryption.with_request_cache { @mgr.encrypt('z', context: @ctx) }
[Fiber[:familia_request_cache], Fiber[:familia_request_cache_enabled]]
#=> [nil, false]

## clear_request_cache! is idempotent and safe to call directly
Familia::Encryption.clear_request_cache!
Fiber[:familia_request_cache]
#=> nil

# TEARDOWN
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
