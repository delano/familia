# try/bug_fixes/stringkey_exists_try.rb
#
# frozen_string_literal: true

# Regression (#331): Familia::DataType#exists? checked
# `dbclient.exists(dbkey) && !size.zero?`. EXISTS returns an Integer (0 for a
# missing key), and 0 is truthy in Ruby, so the left operand never
# short-circuited -- the result was governed entirely by `!size.zero?`. For
# StringKey (and its Counter/Lock subclasses), #char_count derived from
# #to_s.size, and #to_s deliberately falls back to Familia::Base's "never
# nil" inspect-string (e.g. "#<Familia::StringKey:0x...>") when the value is
# nil, per that method's documented contract. That made #size/#char_count
# non-zero -- and #empty? false -- even for a deleted/never-created key.
#
# Fixed on two fronts:
#   - #exists? now relies solely on a boolean-coerced EXISTS count
#     (Familia.positive?), not on #size at all.
#   - #char_count now reads from #value directly instead of #to_s, so it
#     reflects the actual stored content rather than the display fallback.
#     #to_s itself is intentionally untouched -- its never-nil contract is
#     shared by every Familia::Base object.

require_relative '../support/helpers/test_helpers'

@str = Familia::StringKey.new 'test:bugfix:stringkey_exists'
@counter = Familia::Counter.new 'test:bugfix:counter_exists'
@lock = Familia::Lock.new 'test:bugfix:lock_exists'

@str.delete!
@counter.delete!
@lock.delete!

## StringKey#exists? is false for a key that has never existed
@str.exists?
#=> false

## StringKey#exists? returns a real boolean, not a Future/Integer leak
@str.exists?.class
#=> FalseClass

## StringKey#exists? is true once a value is set
@str.value = 'hello'
@str.exists?
#=> true

## StringKey#exists? is false again after delete!
@str.delete!
@str.exists?
#=> false

## StringKey#size is 0 for a key that has never existed
@str.size
#=> 0

## StringKey#empty? is true for a key that has never existed
@str.empty?
#=> true

## StringKey#to_s still honors Familia::Base's never-nil contract when unset
[@str.to_s.nil?, @str.to_s.start_with?('#<Familia::StringKey')]
#=> [false, true]

## StringKey#size matches the real value length once set
@str.value = 'hello'
@str.size
#=> 5

## StringKey#empty? is false once a value is set
@str.empty?
#=> false

## StringKey#to_s returns the real value once set (not the inspect fallback)
@str.to_s
#=> 'hello'

## StringKey#size is 0 again after delete!
@str.delete!
@str.size
#=> 0

## StringKey#empty? is true again after delete!
@str.empty?
#=> true

## An explicitly-set empty string is also correctly empty (distinct from nil)
@str.value = ''
[@str.size, @str.empty?]
#=> [0, true]

## Counter#exists? is false for a counter that has never existed
@counter.exists?
#=> false

## Counter#exists? is true once incremented
@counter.increment
@counter.exists?
#=> true

## Counter#exists? is false again after delete!
@counter.delete!
@counter.exists?
#=> false

## Lock#exists? is false for a lock that was never acquired
@lock.exists?
#=> false

## Lock#exists? is true once acquired
@lock.acquire('token1', ttl: 10)
@lock.exists?
#=> true

## Lock#exists? is false again after release
@lock.release('token1')
@lock.exists?
#=> false

## Teardown
@str.delete!
@counter.delete!
@lock.delete!
