# try/bug_fixes/stringkey_exists_try.rb
#
# frozen_string_literal: true

# Regression (#331): Familia::DataType#exists? checked
# `dbclient.exists(dbkey) && !size.zero?`. EXISTS returns an Integer (0 for a
# missing key), and 0 is truthy in Ruby, so the left operand never
# short-circuited -- the result was governed entirely by `!size.zero?`. For
# StringKey (and its Counter/Lock subclasses), #to_s falls back to
# Object#to_s when the value is nil, making #size non-zero even for a
# deleted/never-created key. Net effect: #exists? returned true regardless of
# whether the key was actually present. Fixed to rely solely on a
# boolean-coerced EXISTS count (Familia.positive?).

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
