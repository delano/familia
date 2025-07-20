# try/93_string_coercion_try.rb

require_relative '../lib/familia'
require_relative './test_helpers'

Familia.debug = false

# Error handling: object without proper identifier setup
class ::BadIdentifierTest < Familia::Horreum
  # No identifier method defined - should cause issues
end

@bad_obj = ::BadIdentifierTest.new

# Test polymorphic string usage for Familia objects
@customer_id = 'customer-string-coercion-test'
@customer = Customer.new(@customer_id)
@customer.name = 'John Doe'
@customer.planid = 'premium'
@customer.save

@session_id = 'session-string-coercion-test'
@session = Session.new(@session_id)
@session.custid = @customer_id
@session.useragent = 'Test Browser'
@session.save

# Complex identifier test with array-based identifier
@bone = Bone.new
@bone.token = 'test_token'
@bone.name = 'test_name'


## Basic to_s functionality returns identifier
@customer.to_s
#=> @customer_id

## String interpolation works seamlessly
"Customer: #{@customer}"
#=> "Customer: #{@customer_id}"

## Explicit identifier call returns same value
@customer.to_s == @customer.identifier
#=> true

## Session to_s works with generated identifier
@session.to_s
#=> @session_id

## Method accepting string parameter works with Familia object
def lookup_by_id(id_string)
  id_string.to_s.upcase
end

lookup_by_id(@customer)
#=> @customer_id.upcase

## Hash key assignment using Familia object (implicit string conversion)
@data = {}
@data[@customer] = 'customer_data'
@data[@customer]
#=> 'customer_data'

## Array operations work with mixed types
@mixed_array = [@customer_id, @customer, @session]
@mixed_array.map(&:to_s)
#=> [@customer_id, @customer_id, @session_id]

## String comparison works
@customer.to_s == @customer_id
#=> true

## Join operations work seamlessly
[@customer, 'separator', @session].join(':')
#=> "#{@customer_id}:separator:#{@session_id}"

## Case statement works with string matching
def classify_id(obj)
  case obj.to_s
  when /customer/
    'customer_type'
  when /session/
    'session_type'
  else
    'unknown_type'
  end
end

classify_id(@customer)
#=> 'customer_type'

classify_id(@session)
#=> 'session_type'

## Polymorphic method accepting both strings and Familia objects
def process_identifier(id_or_object)
  # Can handle both string IDs and Familia objects uniformly
  processed_id = id_or_object.to_s
  "processed:#{processed_id}"
end

process_identifier(@customer_id)
#=> "processed:#{@customer_id}"

process_identifier(@customer)
#=> "processed:#{@customer_id}"

## Redis storage using object as string key
@metadata = Familia::HashKey.new 'metadata'
@metadata[@customer] = 'customer_metadata'
@metadata[@customer.to_s] # Same key access
#=> 'customer_metadata'

## Cleanup after test
@metadata.delete!
#=> true

@customer.delete!
#=> true

@session.delete!
#=> true

## to_s handles identifier errors gracefully
@bad_obj.to_s.include?('BadIdentifierTest')
#=> true

## Array-based identifier works with to_s
@bone.to_s
#=> 'test_token:test_name'

## String operations on complex identifier
@bone.to_s.split(':')
#=> ['test_token', 'test_name']

## Cleanup a key that does not exist
@bone.delete!
#=> false

## Cleanup a key that exists
@bone.save
@bone.delete!
#=> true

## Performance consideration: to_s caching behavior
@customer2 = Customer.new('performance-test')
@first_call = @customer2.to_s
@second_call = @customer2.to_s
@first_call == @second_call
#=> true

## Delete customer2
[@customer2.exists?, @customer2.delete!]
#=> [false, false]
