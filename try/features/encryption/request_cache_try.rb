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

## with_request_cache wipes a stale cache a reused fiber may carry, on entry (S6)
# Simulate a fiber reused across requests that still holds a previous cache.
Fiber[:familia_request_cache_enabled] = true
Fiber[:familia_request_cache] = { 'stale' => String.new('leftover') }
@entry_snapshot = Familia::Encryption.with_request_cache do
  # The block must start from a clean slate, not the leftover hash.
  Fiber[:familia_request_cache].dup
end
@entry_snapshot
#=> {}

## And the cache is cleared again after the block
[Fiber[:familia_request_cache], Fiber[:familia_request_cache_enabled]]
#=> [nil, false]

## RequestCacheMiddleware (clear-only) clears stale state before the app runs
Fiber[:familia_request_cache_enabled] = true
Fiber[:familia_request_cache] = { 'stale' => String.new('leftover') }
@seen = nil
app = ->(env) { @seen = [Fiber[:familia_request_cache], Fiber[:familia_request_cache_enabled]]; [200, {}, []] }
mw = Familia::Encryption::RequestCacheMiddleware.new(app)
mw.call({})
@seen
#=> [nil, false]

## RequestCacheMiddleware (clear-only) clears again after the app, even on raise
Fiber[:familia_request_cache_enabled] = true
Fiber[:familia_request_cache] = { 'stale' => String.new('leftover') }
boom = ->(env) { raise 'boom' }
mw = Familia::Encryption::RequestCacheMiddleware.new(boom)
begin
  mw.call({})
rescue RuntimeError
  # expected
end
[Fiber[:familia_request_cache], Fiber[:familia_request_cache_enabled]]
#=> [nil, false]

## RequestCacheMiddleware(enabled: true) provides an active cache to the app
@inside_mw = nil
app = ->(env) { @inside_mw = Fiber[:familia_request_cache].class; [200, {}, []] }
mw = Familia::Encryption::RequestCacheMiddleware.new(app, enabled: true)
mw.call({})
@inside_mw
#=> Hash

## RequestCacheMiddleware(enabled: true) still clears the cache afterwards
[Fiber[:familia_request_cache], Fiber[:familia_request_cache_enabled]]
#=> [nil, false]

# TEARDOWN
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
