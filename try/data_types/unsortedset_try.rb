# try/data_types/set_try.rb

require_relative '../helpers/test_helpers'

@a = Bone.new 'atoken'

## Familia::UnsortedSet#add
ret = @a.tags.add :a
ret.class
#=> Familia::UnsortedSet

## Familia::UnsortedSet#<<
ret = @a.tags << :a << :b << :c
ret.class
#=> Familia::UnsortedSet

## Familia::UnsortedSet#members
@a.tags.members.sort
#=> ['a', 'b', 'c']

## Familia::UnsortedSet#member? knows when a value exists
@a.tags.member? :a
#=> true

## Familia::UnsortedSet#member? knows when a value doesn't exist
@a.tags.member? :x
#=> false

## Familia::UnsortedSet#member? knows when a value doesn't exist
@a.tags.size
#=> 3

@a.tags.delete!
