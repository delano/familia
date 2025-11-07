# try/unit/data_types/string_try.rb
#
# frozen_string_literal: true

# try/data_types/string_try.rb

require_relative '../../support/helpers/test_helpers'

@a = Bone.new(token: 'atoken2')

## Bone#dbkey
@a.dbkey
#=> 'bone:atoken2:object'

## Familia::StringKey#value should give default value
@a.value.value
#=> 'GREAT!'

## Familia::StringKey#value=
@a.value.value = 'DECENT!'
#=> 'DECENT!'

## Familia::StringKey#to_s
@a.value.to_s
#=> 'DECENT!'

## Familia::StringKey#destroy!
@a.value.delete!
#=> 1

## Familia::StringKey.new
@ret = Familia::StringKey.new 'arbitrary:key'
@ret.dbkey
#=> 'arbitrary:key'

## instance set
@ret.value = '1000'
#=> '1000'

## instance get
@ret.value
#=> '1000'

## Familia::StringKey#increment
@ret.increment
#=> 1001

## Familia::StringKey#incrementby
@ret.incrementby 99
#=> 1100

## Familia::StringKey#decrement
@ret.decrement
#=> 1099

## Familia::StringKey#decrementby
@ret.decrementby 49
#=> 1050

## Familia::StringKey#append
@ret.append 'bytes'
#=> 9

## Familia::StringKey#value after append
@ret.value
#=> '1050bytes'

@ret.delete!
