require 'familia'
require 'familia/test_helpers'

Familia.apiversion = 'v1'

@a = Bone.new 'atoken2', 'akey'

## Bone#rediskey
@a.rediskey
#=> 'v1:bone:atoken2:akey:object'

## Familia::String#value should give default value
@a.value.value
#=> 'GREAT!'

## Familia::String#value=
@a.value.value = "DECENT!"
#=> 'DECENT!'

## Familia::String#to_s
@a.value.to_s
#=> 'DECENT!'

## Familia::String#destroy!
@a.value.destroy!
#=> 1

## Familia::String.new
@ret = Familia::String.new 'arbitrary:key'
@ret.rediskey
#=> 'v1:arbitrary:key'

## instance set
@ret.value = '1000'
#=> '1000'

## instance get
@ret.value
#=> '1000'

@ret.destroy!
