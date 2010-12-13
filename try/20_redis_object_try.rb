
require 'familia'
require 'familia/test_helpers'
Familia.apiversion = 'v1'


## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken'
@b = Bone.new 'btoken'
@a.owners.rediskey == @b.owners.rediskey
#=> false

## Familia objects have no writer method for redis objects
@a.respond_to? :owners=
#=> false

## Redis Objects are frozen 
@a.owners.frozen?
#=> true



