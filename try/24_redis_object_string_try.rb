require 'familia'
require 'familia/test_helpers'


@a = Bone.new 'atoken2', 'akey'

## Bone#rediskey
@a.rediskey
#=> 'bone:atoken2:akey:object'

## Familia::String#value should give default value
@a.value.value
#=> 'GREAT!'

## Familia::String#value=
@a.value.value = "DECENT!"
#=> 'DECENT!'

## Familia::String#to_s
@a.value.to_s
#=> 'DECENT!'

@a.value.destroy!
