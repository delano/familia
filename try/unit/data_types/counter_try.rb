# try/unit/data_types/counter_try.rb
#
# frozen_string_literal: true

# try/data_types/counter_try.rb

require_relative '../../support/helpers/test_helpers'

@a = Bone.new(token: 'atoken3')

## Bone#dbkey
@a.dbkey
#=> 'bone:atoken3:object'

## Familia::Counter should have default value of 0
@a.counter.value
#=> 0

## Familia::Counter#value=
@a.counter.value = 42
#=> 42

## Familia::Counter#to_i
@a.counter.to_i
#=> 42

## Familia::Counter#to_s
@a.counter.to_s
#=> '42'

## Familia::Counter#increment
@a.counter.increment
#=> 43

## Familia::Counter#incrementby
@a.counter.incrementby(10)
#=> 53

## Familia::Counter#decrement
@a.counter.decrement
#=> 52

## Familia::Counter#decrementby
@a.counter.decrementby(5)
#=> 47

## Familia::Counter#reset with value
@a.counter.reset(100)
#=> true

## Familia::Counter#reset without value (defaults to 0)
@a.counter.reset
@a.counter.reset
@a.counter.value
#=> 0

## Familia::Counter#atomic_increment_and_get
@a.counter.atomic_increment_and_get(25)
#=> 25

## Familia::Counter#increment_if_less_than (success case)
@a.counter.increment_if_less_than(50, 10)
#=> true

## Familia::Counter#value after conditional increment
@a.counter.to_i
#=> 35

## Familia::Counter#increment_if_less_than (failure case)
@a.counter.increment_if_less_than(30, 10)
#=> false

## Familia::Counter#value unchanged after failed conditional increment
@a.counter.to_i
#=> 35

## Familia::Counter.new standalone
@counter = Familia::Counter.new 'test:counter'
@counter.dbkey
#=> 'test:counter'

## Standalone counter starts at 0
@counter.value
#=> 0

## Standalone counter increment
@counter.increment
#=> 1

## Standalone counter set string value gets coerced to integer
@counter.value = "123"
@counter.to_i
#=> 123

# Cleanup
@a.counter.delete!
@counter.delete!
