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

## Familia::Object.class_list
Customer.customers.class
#=> Familia::Object::List

## Familia::Object class rediskey
Customer.customers.rediskey
#=> 'v1:customer:customers'

## Familia::Object.class_list
Customer.customers << :delano << :tucker << :morton
Customer.customers.size
#=> 3

## Familia::Object class clear
Customer.customers.clear
##=> 1


## Familia::Object class replace 1
Customer.message.value = "msg1"
#=> "msg1"

## Familia::Object class replace 2
Customer.message.value
#=> "msg1"

## Familia::Object class replace 3
Customer.message = "msg2"
#=> "msg2"

## Familia::Object class replace 4
Customer.message.value
#=> "msg2"

