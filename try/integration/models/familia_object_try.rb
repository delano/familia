# try/integration/models/familia_object_try.rb
#
# frozen_string_literal: true

# try/models/familia_object_try.rb

require_relative '../../support/helpers/test_helpers'

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
#=:> MultiResult
#==> result.successful?

## Customer.instances
Customer.values.size
#=> 0

## Familia#save with an object that expires
obj = Session.new 'sessionid'
obj.save
#=> true

## Familia.class_list
Customer.all_customers.class
#=> Familia::ListKey

## Familia class dbkey
Customer.all_customers.dbkey
#=> 'customer:all_customers'

## Familia.class_list
Customer.all_customers << :delano << :tucker << :morton
Customer.all_customers.size
#=> 3

## Familia class clear
Customer.all_customers.delete!
#=> 1

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
