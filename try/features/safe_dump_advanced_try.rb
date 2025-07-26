# try/features/safe_dump_extended_try.rb

# These tryouts test the safe dumping functionality.

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

## By default Familia::Base has no safe_dump_fields method
Familia::Base.respond_to?(:safe_dump_fields)
#=> false

## Implementing models like Customer can define safe dump fields
Customer.safe_dump_fields
#=> [:custid, :role, :verified, :updated, :created, :secrets_created, :active]

## Implementing models like Customer can safely dump their fields
@cust = Customer.new
@cust.custid = 'test@example.com'
@cust.role = 'user'
@cust.verified = true
@cust.created = Time.now.to_i
@cust.updated = Time.now.to_i
@safe_dump = @cust.safe_dump
@safe_dump.keys.sort
#=> [:active, :created, :custid, :role, :secrets_created, :updated, :verified]

## Implementing models like Customer do have other fields
## that are by default considered not safe to dump.
@cust1 = Customer.new
@cust1.email = 'test@example.com'

@all_non_safe_fields = @cust1.instance_variables.map do |el|
  el.to_s[1..-1].to_sym # slice off the leading @
end.sort

(@all_non_safe_fields - Customer.safe_dump_fields).sort
#=> [:custom_domains, :email, :password_reset, :sessions, :stripe_customer, :timeline]

## Implementing models like Customer can rest assured knowing
## any other field not in the safe list will not be dumped.
@cust2 = Customer.new
@cust2.email = 'test@example.com'
@cust2.custid = 'test@example.com'
@all_safe_fields = @cust2.safe_dump.keys.sort
@all_non_safe_fields = @cust2.instance_variables.map do |el|
  el.to_s[1..-1].to_sym # slice off the leading @
end.sort
# Check if any of the non-safe fields are in the safe dump (tryouts bug
# if this comment is placed right before the last line.)
p [1, { all_non_safe_fields: @all_non_safe_fields }]
(@all_non_safe_fields & @all_safe_fields) - %i[custid role verified updated created secrets_created]
#=> []

## Bone does not have safe_dump feature enabled
Bone.respond_to?(:safe_dump_fields)
#=> false

## Bone instances do not have safe_dump method
@bone = Bone.new(token: 'boneid1', name: 'Rex')
@bone.respond_to?(:safe_dump)
#=> false

## Blone has safe_dump feature enabled
Blone.respond_to?(:safe_dump_fields)
#=> true

## Blone has empty safe_dump_fields
Blone.safe_dump_fields
#=> []

## Blone instances have safe_dump method
@blone = Blone.new(name: 'Fido', age: 5)
@blone.respond_to?(:safe_dump)
#=> true

## Blone safe_dump returns an empty hash
@blone.safe_dump
#=> {}

# Teardown
@cust2.destroy!
@bone = nil
@blone = nil
