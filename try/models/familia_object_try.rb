# try/models/familia_object_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

@a = Session.new 'atoken'

## Familia.prefix
Session.prefix
#=> :session

## Familia#identifier
@a.identifier
#=> 'atoken'

## Familia.suffix
Session.suffix
#=> :object

## Familia#dbkey
@a.dbkey
#=> 'session:atoken:object'

## Familia#dbkey
@a.dbkey
#=> 'session:atoken:object'

## Familia#save
@cust = Customer.new :delano, 'Delano Mandelbaum'
@cust.save
#=> true

## Customer.values (Updateing this sorted set of instance IDs is a Onetime
# Secret feature. Disabled here b/c there's no code in Familia or the test
# helpers that replicates this behaviour.) Leaving this here for reference.
Customer.values.all.collect(&:custid)
##=> ['delano']

## Can load an object from an identifier
obj = Customer.find_by_id :delano
[obj.class, obj.custid]
#=> [Customer, 'delano']

## Customer.destroy
@cust.destroy!
#=> true

## Customer.instances
Customer.values.size
#=> 0

## Familia#save with an object that expires
obj = Session.new 'sessionid'
obj.save
#=> true

## Familia.class_list
Customer.customers.class
#=> Familia::List

## Familia class dbkey
Customer.customers.dbkey
#=> 'customer:customers'

## Familia.class_list
Customer.customers << :delano << :tucker << :morton
Customer.customers.size
#=> 3

## Familia class clear
Customer.customers.delete!
#=> true

## Familia class replace 1 of 4
Customer.message.value = 'msg1'
#=> "msg1"

## Familia class replace 2 of 4
Customer.message.value
#=> "msg1"

## Familia class replace 3 of 4
Customer.message = 'msg2'
#=> "msg2"

## Familia class replace 4 of 4
Customer.message.value
#=> "msg2"

# Teardown
Customer.values.delete!
