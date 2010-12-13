require 'familia'
require 'familia/test_objects'


@a = Bone.new 'atoken'

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
