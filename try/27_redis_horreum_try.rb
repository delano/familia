require_relative '../lib/familia'
require_relative './test_helpers'

Familia.debug = true

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
@hashkey.clear
#=> 1
