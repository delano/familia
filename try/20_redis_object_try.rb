
require 'familia'
require 'familia/test_objects'
Familia.apiversion = 'v1'


## Redis Objects are unique per instance of a Familia class
@a = Bone.new 'atoken'
@b = Bone.new 'btoken'
@a.owners.rediskey == @b.owners.rediskey
#=> false





