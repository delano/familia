require_relative '../support/helpers/test_helpers'

# Test class for count/any method testing
class CountTestCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
end

# Setup - clear any existing data
CountTestCustomer.instances.clear
CountTestCustomer.all.each(&:destroy!)

## count returns 0 when no instances exist
CountTestCustomer.count
#=> 0

## count! returns 0 when no instances exist
CountTestCustomer.count!
#=> 0

## any? returns false when no instances exist
CountTestCustomer.any?
#=> false

## any! returns false when no instances exist
CountTestCustomer.any!
#=> false

## count returns 1 after creating an instance
@cust1 = CountTestCustomer.create!(custid: 'alice', name: 'Alice')
CountTestCustomer.count
#=> 1

## count! returns 1 after creating an instance
CountTestCustomer.count!
#=> 1

## any? returns true after creating an instance
CountTestCustomer.any?
#=> true

## any! returns true after creating an instance
CountTestCustomer.any!
#=> true

## count increases after creating another instance
@cust2 = CountTestCustomer.create!(custid: 'bob', name: 'Bob')
CountTestCustomer.count
#=> 2

## count! also shows 2 instances
CountTestCustomer.count!
#=> 2

## count! with filter matches specific patterns
@cust3 = CountTestCustomer.create!(custid: 'alice2', name: 'Alice2')
CountTestCustomer.count!('alice*')
#=> 2

## any! with filter detects matching patterns
CountTestCustomer.any!('alice*')
#=> true

## any! with filter returns false for non-matching patterns
CountTestCustomer.any!('nonexistent*')
#=> false

## count reflects deletion when object is destroyed via Familia
@cust1.destroy!
CountTestCustomer.count
#=> 2

## count! also reflects the deletion
CountTestCustomer.count!
#=> 2

## count shows stale data when instance deleted outside Familia
# Delete directly from Redis without going through Familia
CountTestCustomer.dbclient.del(@cust2.dbkey)
CountTestCustomer.count
#=> 2

## count! shows authoritative data after direct deletion
CountTestCustomer.count!
#=> 1

## any? may return true even when all objects deleted outside Familia
# Instance tracking still has entries
CountTestCustomer.any?
#=> true

## any! returns false when no actual keys exist
CountTestCustomer.dbclient.del(@cust3.dbkey)
CountTestCustomer.any!
#=> false

## scan_count alias works correctly
@cust4 = CountTestCustomer.create!(custid: 'charlie', name: 'Charlie')
CountTestCustomer.scan_count
#=> 1

## size alias works correctly (uses matching_keys_count)
CountTestCustomer.size
#=> 1

## length alias works correctly (uses matching_keys_count)
CountTestCustomer.length
#=> 1

# Cleanup
CountTestCustomer.instances.clear
CountTestCustomer.all.each(&:destroy!)
