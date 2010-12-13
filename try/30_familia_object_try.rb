require 'familia'
require 'familia/test_helpers'
Familia.apiversion = 'v1'

@a = Bone.new 'atoken', 'akey'

## Familia::Object.prefix
Bone.prefix
#=> :bone

## Familia::Object#index
@a.index
#=> 'atoken:akey'

## Familia::Object.suffix
Bone.suffix
#=> :object

## Familia::Object#rediskey
@a.rediskey
#=> 'v1:bone:atoken:akey:object'

## Familia::Object#rediskey
@a.rediskey
#=> 'v1:bone:atoken:akey:object'

## Familia::Object#save
obj = Customer.new :delano, "Delano Mandelbaum"
obj.save
#=> true

## Familia::Object#save with an object that expires
obj = Session.new 'sessionid', :delano
obj.save
#=> true

## Familia::Object.from_redis
obj = Customer.from_redis :delano
obj.custid
#=> :delano

