require 'familia'
require 'familia/test_helpers'


@a = Bone.new 'atoken', 'akey'

## Familia::Object::String#value should give default value
@a.msg.value
#=> 'GREAT!'

## Familia::Object::String#value=
@a.msg.value = "DECENT!"
#=> 'DECENT!'

## Familia::Object::String#to_s
@a.msg.to_s
#=> 'DECENT!'

@a.msg.destroy!
