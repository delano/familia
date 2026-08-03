# try/unit/data_types/lock_try.rb
#
# frozen_string_literal: true

# try/data_types/lock_try.rb

require_relative '../../support/helpers/test_helpers'

@a = Bone.new(token: 'atoken4')

## Bone#dbkey
@a.dbkey
#=> 'bone:atoken4:object'

## Familia::Lock should start unlocked
@a.lock.locked?
#=> false

## Familia::Lock#value should be nil when unlocked
@a.lock.value
#=> nil

## Familia::Lock#acquire returns token when successful
@token1 = @a.lock.acquire
@token1.class
#=> String

## Familia::Lock#locked? after acquire
@a.lock.locked?
#=> true

## Familia::Lock#held_by? with correct token
@a.lock.held_by?(@token1)
#=> true

## Familia::Lock#held_by? with wrong token
@a.lock.held_by?('wrong-token')
#=> false

## Familia::Lock#acquire when already locked returns false
@a.lock.acquire
#=> false

## Familia::Lock#release with correct token
@a.lock.release(@token1)
#=> true

## Familia::Lock#locked? after release
@a.lock.locked?
#=> false

## Familia::Lock#release with wrong token (lock not held)
@a.lock.release('wrong-token')
#=> false

## Familia::Lock#acquire with custom token
@custom_token = 'my-custom-token-123'
@result = @a.lock.acquire(@custom_token)
@result
#=> 'my-custom-token-123'

## Familia::Lock#held_by? with custom token
@a.lock.held_by?(@custom_token)
#=> true

## Familia::Lock#force_unlock!
@a.lock.force_unlock!
#=> true

## Familia::Lock#locked? after force unlock
@a.lock.locked?
#=> false

## Familia::Lock.new standalone
@lock = Familia::Lock.new 'test:lock'
@lock.dbkey
#=> 'test:lock'

## Standalone lock starts unlocked
@lock.locked?
#=> false

## Standalone lock acquire
@standalone_token = @lock.acquire
@standalone_token.class
#=> String

## Standalone lock is now locked
@lock.locked?
#=> true

## Standalone lock acquire with TTL
@lock.force_unlock!
@ttl_token = @lock.acquire('ttl-token', ttl: 1)
@ttl_token
#=> 'ttl-token'

## Lock acquired with TTL registers an expiration
@lock.current_expiration.positive?
#=> true

## Lock auto-expires once its TTL elapses
# Poll with a bounded deadline instead of a single fixed sleep: the key
# expires ~1s after acquisition; allow up to 3s for slow/loaded runners.
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
sleep 0.05 while @lock.locked? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
@lock.locked?
#=> false

## Acquire with zero TTL should return false
@lock2 = Familia::Lock.new 'test:lock2'
@lock2.acquire('zero-ttl', ttl: 0)
#=> false

## Lock should not be held after zero TTL rejection
@lock2.locked?
#=> false

## Acquire with negative TTL should return false
@lock2.acquire('neg-ttl', ttl: -5)
#=> false

## Lock should not be held after negative TTL rejection
@lock2.locked?
#=> false

## Acquire with nil TTL should work (no expiration)
@nil_ttl_token = @lock2.acquire('no-expiry', ttl: nil)
@nil_ttl_token
#=> 'no-expiry'

## Lock with nil TTL should be held
@lock2.locked?
#=> true

## Lock with nil TTL should not have expiration
@lock2.current_expiration
#=> -1

## Fresh acquire with positive TTL sets expiration atomically (SET NX EX):
## the expiry must be present immediately after a successful acquire, never
## a TTL-less key from a SETNX-then-EXPIRE gap.
@lock3 = Familia::Lock.new 'test:lock3'
@atomic_token = @lock3.acquire('atomic-token', ttl: 30)
[@atomic_token, @lock3.current_expiration.positive?]
#=> ['atomic-token', true]

## Cleanup
@a.lock.delete!
@lock.delete!
@lock2.delete!
@lock3.delete!
