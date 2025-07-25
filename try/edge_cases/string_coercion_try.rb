# try/edge_cases/string_coercion_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

@customer_id = 'customer-string-coercion-test'

# Error handling: object without proper identifier setup
class ::BadIdentifierTest < Familia::Horreum
  # No identifier method defined - should cause issues
end

# Case statement works with string matching
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

# Polymorphic method accepting both strings and Familia objects
def process_identifier(id_or_object)
  # Can handle both string IDs and Familia objects uniformly
  processed_id = id_or_object.to_s
  "processed:#{processed_id}"
end

def lookup_by_id(id_string)
  id_string.to_s.upcase
end

## Instantiaite a troubled model class
@bad_obj = ::BadIdentifierTest.new
#=:> BadIdentifierTest

# Test polymorphic string usage for Familia objects
@customer = Customer.new(@customer_id)
@customer.name = 'John Doe'
@customer.planid = 'premium'
@customer.save
#=> true

## Session save
@session = Session.new
@session.custid = @customer_id
@session.useragent = 'Test Browser'
@session.save
#=> true

## Bone with simple identifier
@bone = Bone.new
@bone.token = 'test_token'
@bone.name = 'test_name'
@bone.identifier
#=> 'test_token'

## Basic to_s functionality returns identifier
@customer.to_s
#=> @customer_id

## String interpolation works seamlessly
"Customer: #{@customer}"
#=> "Customer: #{@customer_id}"

## Explicit identifier call returns same value
@customer.to_s == @customer.identifier
#=> true

## Session identifier can be set and is not overidden even after saved
@session_id = 'session-string-coercion-test'
session = Session.new(@session_id)
session.identifier
session
#==> _.to_s == @session_id
#==> _.identifier == @session_id
#==> _.save
#==> _.identifier == @session_id
#==> _.to_s == @session_id

## Session to_s works with generated identifier
@session.to_s
#=<> @session_id

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
#=> [@customer_id, @customer_id, _[2]]

## String comparison works
@customer.to_s == @customer_id
#=> true

## Join operations work seamlessly
[@customer, 'separator', @session].join(':')
#=~> /\A#{@customer_id}:separator:[0-9a-z]+\z/

## Classify a customer
classify_id(@customer)
#=> 'customer_type'

## Polymorphic method accepting both strings and Familia objects (string)
process_identifier(@customer_id)
#=> "processed:#{@customer_id}"

## Polymorphic method accepting both strings and Familia objects (familia)
process_identifier(@customer)
#=> "processed:#{@customer_id}"

## Database storage using object as string key
@metadata = Familia::HashKey.new 'metadata'
@metadata[@customer] = 'customer_metadata'
@metadata[@customer.to_s] # Same key access
#=> 'customer_metadata'

## Cleanup after test, 1
@metadata.delete!
#=> true

## Cleanup after test, 2
@customer.delete!
#=> true

## Cleanup after test, 3
@session.delete!
#=> true

## to_s handles identifier errors gracefully
badboi = BadIdentifierTest.new
badboi.to_s #.include?('BadIdentifierTest')
#=~> /BadIdentifierTest:0x[0-9a-f]+/

## Performance consideration: to_s caching behavior
@customer2 = Customer.new('performance-test')
@first_call = @customer2.to_s
@second_call = @customer2.to_s
@first_call == @second_call
#=> true

## Delete customer2
[@customer2.exists?, @customer2.delete!]
#=> [false, false]
