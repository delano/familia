require_relative '../lib/familia'
require_relative './test_helpers'

Familia.debug = false

@identifier = 'tryouts-27@onetimesecret.com'
@customer = Customer.new @identifier
@hashkey = Familia::HashKey.new 'tryouts-27'

## Customer passed as value is returned as string identifier, on assignment as string
@hashkey["test1"] = @customer.identifier
#=> @identifier

## Customer passed as value is returned as string identifier
@hashkey["test1"]
#=> @identifier

## Trying to store a customer to a hash key implicitly converts it to string identifier
## we can't tell from the return value this way either. Here the store method return value
## is either 1 (if the key is new) or 0 (if the key already exists).
@hashkey.store "test2", @customer
#=> 1

## Trying to store a customer to a hash key implicitly converts it to string identifier
## but we can't tell that from the return value. Here the hash syntax return value
## is the value that is being assigned.
@hashkey["test2"] = @customer
#=> @customer

## Trying store again with the same key returns 0
@hashkey.store "test2", @customer
#=> 0

## Customer passed as value is returned as string identifier
@hashkey["test2"]
#=> @identifier

## Remove the key
@hashkey.delete!
#=> true

## Horreum objects can update and save their fields (1 of 2)
@customer.name = 'John Doe'
#=> "John Doe"

## Horreum objects can update and save their fields (2 of 2)
@customer.save
#=> true

## Horreum object fields have a fast attribute method (1 of 2)
Familia.trace :LOAD, @customer.redis, @customer.redisuri, caller if Familia.debug?
@customer.name! 'Jane Doe'
#=> 0

## Horreum object fields have a fast attribute method (2 of 2)
@customer.refresh!
@customer.name
#=> "Jane Doe"

## Unsaved changes are lost when an object reloads
@customer.name = 'John Doe'
@customer.refresh!
@customer.name
#=> "Jane Doe"

## Horreum objects can be destroyed
@customer.destroy!
#=> true

## All horrerum objects have a key field
@customer.key
#=> @identifier

## Even ones that didn't define it
@cd = CustomDomain.new "www.example.com", "@identifier"
@cd.key
#=> nil

## We can call #identifier directly if we want to "lasy load" the unique identifier
@cd.identifier
#=> "7565befd"

## The #key field will still be nil
@cd.key
#=> nil

## But once we save
@cd.save
#=> true

## The key will be set
@cd.key
#=> "7565befd"
