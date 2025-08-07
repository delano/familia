# try/horreum/serialization_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

@identifier = 'tryouts-28@onetimesecret.com'
@customer = Customer.new @identifier

## Basic save functionality works
@customer.name = 'John Doe'
@customer.save
#=> true

## to_h returns field hash with all Customer fields
@customer.to_h.class
#=> Hash

## to_h includes the fields we set (using symbol keys)
@customer.to_h[:name]
#=> "John Doe"

## to_h includes the custid field (using symbol keys)
@customer.to_h[:custid]
#=> "tryouts-28@onetimesecret.com"

## to_a returns field array in definition order
@customer.to_a.class
#=> Array

## to_a includes values in field order (name should be at index 4)
@customer.to_a[4]
#=> "John Doe"

## batch_update can update multiple fields atomically, to_h
@result = @customer.batch_update(name: 'Jane Smith', email: 'jane@example.com')
@result.to_h
#=> {:success=>true, :results=>[0, 0]}

## batch_update returns successful result, successful?
@result.successful?
#=> true

## batch_update returns successful result, tuple
@result.tuple
#=> [true, [0, 0]]

## batch_update returns successful result, to_a
@result.to_a
#=> [true, [0, 0]]

## batch_update updates object fields in memory, confirm fields changed
[@customer.name, @customer.email]
#=> ["Jane Smith", "jane@example.com"]

## batch_update persists to Redis
@customer.refresh!
[@customer.name, @customer.email]
#=> ["Jane Smith", "jane@example.com"]

## batch_update with update_expiration: false works
@customer.batch_update(name: 'Bob Jones', update_expiration: false)
@customer.refresh!
@customer.name
#=> "Bob Jones"

## apply_fields updates object in memory only (1 of 2)
@customer.apply_fields(name: 'Memory Only', email: 'memory@test.com')
[@customer.name, @customer.email]
#=> ["Memory Only", "memory@test.com"]

## apply_fields doesn't persist to Database (2 of 2)
@customer.refresh!
[@customer.name, @customer.email]
#=> ["Bob Jones", "jane@example.com"]

## serialize_value handles strings
@customer.serialize_value('test string')
#=> "test string"

## serialize_value handles numbers
@customer.serialize_value(42)
#=> "42"

## serialize_value handles hashes as JSON
@customer.serialize_value({ key: 'value', num: 123 })
#=> "{\"key\":\"value\",\"num\":123}"

## serialize_value handles arrays as JSON
@customer.serialize_value([1, 2, 'three'])
#=> "[1,2,\"three\"]"

## deserialize_value handles JSON strings back to objects
@customer.deserialize_value('{"key":"value","num":123}')
#=> {:key=>"value", :num=>123}

## deserialize_value handles JSON arrays
@customer.deserialize_value('[1,2,"three"]')
#=> [1, 2, "three"]

## deserialize_value handles plain strings
@customer.deserialize_value('plain string')
#=> "plain string"

## transaction method works with block
result = @customer.transaction do |conn|
  conn.hset @customer.dbkey, 'temp_field', 'temp_value'
  conn.hset @customer.dbkey, 'another_field', 'another_value'
end
result.size
#=> 2

## refresh! reloads from Redis
@customer.refresh!
@customer.hget('temp_field')
#=> "temp_value"

## Empty batch_update still works
result = @customer.batch_update
result.successful?
#=> true

## destroy! removes object from Database (1 of 2)
@customer.destroy!
#=> true

## After destroy!, dbkey no longer exists (2 of 2)
@customer.exists?
#=> false

## destroy! removes object from Redis, not the in-memory object (2 of 2)
@customer.refresh!
@customer.name
#=> "Bob Jones"

## clear_fields! removes the in-memory object fields
@customer.clear_fields!
@customer.name
#=> nil

## Fresh customer for testing new field creation
@fresh_customer = Customer.new 'fresh-customer@test.com'
@fresh_customer.class
#=> Customer

## batch_update with new fields returns [1, 1] for new field creation
@fresh_customer.remove_field('role')
@fresh_customer.remove_field('planid')
@fresh_result = @fresh_customer.batch_update(role: 'admin', planid: 'premium')
@fresh_result.to_h
#=> {:success=>true, :results=>[1, 1]}

## Fresh customer fields are set correctly
[@fresh_customer.role, @fresh_customer.planid]
#=> ["admin", "premium"]

## Fresh customer changes persist to Redis
@fresh_customer.refresh!
[@fresh_customer.role, @fresh_customer.planid]
#=> ["admin", "premium"]
