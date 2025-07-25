# try/datatypes/string_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

@a = Bone.new(token: 'atoken2')

## Bone#dbkey
@a.dbkey
#=> 'bone:atoken2:object'

## Familia::String#value should give default value
@a.value.value
#=> 'GREAT!'

## Familia::String#value=
@a.value.value = 'DECENT!'
#=> 'DECENT!'

## Familia::String#to_s
@a.value.to_s
#=> 'DECENT!'

## Familia::String#destroy!
@a.value.delete!
#=> true

## Familia::String.new
@ret = Familia::String.new 'arbitrary:key'
@ret.dbkey
#=> 'arbitrary:key'

## instance set
@ret.value = '1000'
#=> '1000'

## instance get
@ret.value
#=> '1000'

## Familia::String#increment
@ret.increment
#=> 1001

## Familia::String#incrementby
@ret.incrementby 99
#=> 1100

## Familia::String#decrement
@ret.decrement
#=> 1099

## Familia::String#decrementby
@ret.decrementby 49
#=> 1050

## Familia::String#append
@ret.append 'bytes'
#=> 9

## Familia::String#value after append
@ret.value
#=> '1050bytes'

@ret.delete!
