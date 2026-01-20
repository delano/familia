# try/unit/data_types/stringkey_extended_try.rb
#
# frozen_string_literal: true

# Tests for extended StringKey Redis commands

require_relative '../../support/helpers/test_helpers'

@str = Familia::StringKey.new 'test:stringkey:extended'
@str2 = Familia::StringKey.new 'test:stringkey:extended2'
@str3 = Familia::StringKey.new 'test:stringkey:extended3'

## Setup: set initial value (Ruby assignment returns the assigned value)
@str.value = '100'
#=> '100'

## incrbyfloat increments by a float value
@str.incrbyfloat(0.5)
#=> 100.5

## incrbyfloat with negative value
@str.incrbyfloat(-0.25)
#=> 100.25

## incrfloat alias works
@str.incrfloat(0.75)
#=> 101.0

## setex sets value with expiration
@str2.setex(10, 'temporary')
@str2.value
#=> 'temporary'

## setex key has TTL
@str2.ttl > 0
#=> true

## psetex sets value with millisecond expiration
@str3.psetex(5000, 'ms_temp')
@str3.value
#=> 'ms_temp'

## psetex key has TTL (in seconds, so should be > 0)
@str3.ttl > 0
#=> true

## getdel returns value and deletes
@str.value = 'getdel_test'
result = @str.getdel
[result, @str.value]
#=> ['getdel_test', nil]

## getex returns value
@str.value = 'getex_test'
@str.getex
#=> 'getex_test'

## getex with ex sets expiration
@str.getex(ex: 30)
@str.ttl > 0
#=> true

## bitcount on empty string
@str.delete!
@str.bitcount
#=> 0

## bitcount after setting value ('f'=6bits, 'o'=4bits: 6+4+4+6=20)
@str.value = 'foof'
@str.bitcount
#=> 20

## bitcount with range
@str.bitcount(0, 1)
#=> 10

## bitpos finds first set bit
@str.value = "\x00\xff"
@str.bitpos(1)
#=> 8

## bitpos finds first unset bit
@str.bitpos(0)
#=> 0

## bitpos with start position
@str.bitpos(1, 1)
#=> 8

## bitfield GET operation
@str.delete!
@str.setbit(0, 1)
@str.setbit(1, 1)
@str.setbit(2, 1)
@str.bitfield('GET', 'u8', 0)
#=> [224]

## bitfield SET operation
@str.delete!
@str.bitfield('SET', 'u8', 0, 100)
@str.bitfield('GET', 'u8', 0)
#=> [100]

## mget retrieves multiple keys (pass hash with braces to avoid kwarg interpretation)
Familia::StringKey.mset({ 'mget:test:1' => 'one', 'mget:test:2' => 'two' })
Familia::StringKey.mget('mget:test:1', 'mget:test:2', 'mget:test:nonexistent')
#=> ['one', 'two', nil]

## mset sets multiple keys atomically
Familia::StringKey.mset({ 'mset:test:a' => 'alpha', 'mset:test:b' => 'beta' })
[Familia.dbclient.get('mset:test:a'), Familia.dbclient.get('mset:test:b')]
#=> ['alpha', 'beta']

## msetnx sets only if all keys don't exist
Familia.dbclient.del('msetnx:test:1', 'msetnx:test:2')
result1 = Familia::StringKey.msetnx({ 'msetnx:test:1' => 'first', 'msetnx:test:2' => 'second' })
result2 = Familia::StringKey.msetnx({ 'msetnx:test:1' => 'new', 'msetnx:test:3' => 'third' })
[result1, result2]
#=> [true, false]

## bitop performs bitwise AND (returns size of resulting string)
# Clean up any stale keys first, use simple ASCII strings to avoid encoding issues
Familia.dbclient.del('stringkey_ext:bitop:a', 'stringkey_ext:bitop:b', 'stringkey_ext:bitop:result')
Familia.dbclient.set('stringkey_ext:bitop:a', 'abc')
Familia.dbclient.set('stringkey_ext:bitop:b', 'ABC')
result_size = Familia::StringKey.bitop(:and, 'stringkey_ext:bitop:result', 'stringkey_ext:bitop:a', 'stringkey_ext:bitop:b')
result_size
#=> 3

## bitop AND produces expected result (lowercase AND uppercase = uppercase)
# 'a' (0x61) AND 'A' (0x41) = 0x41 = 'A', same for b/B and c/C
Familia.dbclient.get('stringkey_ext:bitop:result')
#=> "ABC"

## bitop performs bitwise OR (returns size of resulting string)
Familia.dbclient.del('stringkey_ext:bitop:c', 'stringkey_ext:bitop:d', 'stringkey_ext:bitop:or_result')
Familia.dbclient.set('stringkey_ext:bitop:c', 'abc')
Familia.dbclient.set('stringkey_ext:bitop:d', 'ABC')
result_size = Familia::StringKey.bitop(:or, 'stringkey_ext:bitop:or_result', 'stringkey_ext:bitop:c', 'stringkey_ext:bitop:d')
result_size
#=> 3

## bitop OR produces expected result (lowercase OR uppercase = lowercase)
Familia.dbclient.get('stringkey_ext:bitop:or_result')
#=> "abc"

## Teardown
@str.delete!
@str2.delete!
@str3.delete!
Familia.dbclient.del('mget:test:1', 'mget:test:2')
Familia.dbclient.del('mset:test:a', 'mset:test:b')
Familia.dbclient.del('msetnx:test:1', 'msetnx:test:2', 'msetnx:test:3')
Familia.dbclient.del('stringkey_ext:bitop:a', 'stringkey_ext:bitop:b', 'stringkey_ext:bitop:c', 'stringkey_ext:bitop:d', 'stringkey_ext:bitop:result', 'stringkey_ext:bitop:or_result')
