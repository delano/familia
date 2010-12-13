require 'familia'
require 'familia/test_helpers'


@a = Bone.new 'atoken', 'akey'

## Familia::Object::String#value should give default value
@a.value.value
#=> 'GREAT!'

## Familia::Object::String#value=
@a.value.value = "DECENT!"
#=> 'DECENT!'

## Familia::Object::String#to_s
@a.value.to_s
#=> 'DECENT!'

@a.value.destroy!
