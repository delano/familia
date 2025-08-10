# try/data_types/lock_try.rb

require_relative '../helpers/test_helpers'

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

## Wait for TTL expiration and check if lock auto-expires
# Note: This test might be flaky in fast test runs
sleep 2
@lock.locked?
#=> false

## Cleanup
@a.lock.delete!
@lock.delete!
