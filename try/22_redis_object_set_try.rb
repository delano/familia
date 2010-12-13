
require 'familia'
require 'familia/test_helpers'

@a = Bone.new 'atoken', 'akey'

## Familia::Object::Set#add
ret = @a.tags.add :a
ret.class
#=> Familia::Object::Set

## Familia::Object::Set#<<
ret = @a.tags << :a << :b << :c
ret.class
#=> Familia::Object::Set

## Familia::Object::Set#members
@a.tags.members.sort
#=> ['a', 'b', 'c']

## Familia::Object::Set#member? knows when a value exists
@a.tags.member? :a
#=> true

## Familia::Object::Set#member? knows when a value doesn't exist
@a.tags.member? :x
#=> false

## Familia::Object::Set#member? knows when a value doesn't exist
@a.tags.size
#=> 3


@a.tags.destroy!
