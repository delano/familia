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

## keys_count returns 0 when no instances exist (KEYS command)
CountTestCustomer.keys_count
#=> 0

## scan_count returns 0 when no instances exist (SCAN command)
CountTestCustomer.scan_count
#=> 0

## count! returns 0 when no instances exist (alias to scan_count)
CountTestCustomer.count!
#=> 0

## any? returns false when no instances exist
CountTestCustomer.any?
#=> false

## keys_any? returns false when no instances exist (KEYS command)
CountTestCustomer.keys_any?
#=> false

## scan_any? returns false when no instances exist (SCAN command)
CountTestCustomer.scan_any?
#=> false

## any! returns false when no instances exist (alias to scan_any?)
CountTestCustomer.any!
#=> false

## count returns 1 after creating an instance
@cust1 = CountTestCustomer.create!(custid: 'alice', name: 'Alice')
CountTestCustomer.count
#=> 1

## keys_count returns 1 after creating an instance
CountTestCustomer.keys_count
#=> 1

## scan_count returns 1 after creating an instance
CountTestCustomer.scan_count
#=> 1

## count! returns 1 after creating an instance
CountTestCustomer.count!
#=> 1

## any? returns true after creating an instance
CountTestCustomer.any?
#=> true

## keys_any? returns true after creating an instance
CountTestCustomer.keys_any?
#=> true

## scan_any? returns true after creating an instance
CountTestCustomer.scan_any?
#=> true

## any! returns true after creating an instance
CountTestCustomer.any!
#=> true

## count increases after creating another instance
@cust2 = CountTestCustomer.create!(custid: 'bob', name: 'Bob')
CountTestCustomer.count
#=> 2

## keys_count also shows 2 instances
CountTestCustomer.keys_count
#=> 2

## scan_count also shows 2 instances
CountTestCustomer.scan_count
#=> 2

## count! also shows 2 instances
CountTestCustomer.count!
#=> 2

## keys_count with filter matches specific patterns
@cust3 = CountTestCustomer.create!(custid: 'alice2', name: 'Alice2')
CountTestCustomer.keys_count('alice*')
#=> 2

## scan_count with filter matches specific patterns
CountTestCustomer.scan_count('alice*')
#=> 2

## count! with filter matches specific patterns
CountTestCustomer.count!('alice*')
#=> 2

## keys_any? with filter detects matching patterns
CountTestCustomer.keys_any?('alice*')
#=> true

## scan_any? with filter detects matching patterns
CountTestCustomer.scan_any?('alice*')
#=> true

## any! with filter detects matching patterns
CountTestCustomer.any!('alice*')
#=> true

## keys_any? with filter returns false for non-matching patterns
CountTestCustomer.keys_any?('nonexistent*')
#=> false

## scan_any? with filter returns false for non-matching patterns
CountTestCustomer.scan_any?('nonexistent*')
#=> false

## any! with filter returns false for non-matching patterns
CountTestCustomer.any!('nonexistent*')
#=> false

## count reflects deletion when object is destroyed via Familia
@cust1.destroy!
CountTestCustomer.count
#=> 2

## keys_count also reflects the deletion
CountTestCustomer.keys_count
#=> 2

## scan_count also reflects the deletion
CountTestCustomer.scan_count
#=> 2

## count! also reflects the deletion
CountTestCustomer.count!
#=> 2

## count shows stale data when instance deleted outside Familia
# Delete directly from Redis without going through Familia
CountTestCustomer.dbclient.del(@cust2.dbkey)
CountTestCustomer.count
#=> 2

## keys_count shows authoritative data after direct deletion
CountTestCustomer.keys_count
#=> 1

## scan_count shows authoritative data after direct deletion
CountTestCustomer.scan_count
#=> 1

## count! shows authoritative data after direct deletion
CountTestCustomer.count!
#=> 1

## any? may return true even when all objects deleted outside Familia
# Instance tracking still has entries
CountTestCustomer.any?
#=> true

## keys_any? returns false when no actual keys exist
CountTestCustomer.dbclient.del(@cust3.dbkey)
CountTestCustomer.keys_any?
#=> false

## scan_any? returns false when no actual keys exist
CountTestCustomer.scan_any?
#=> false

## any! returns false when no actual keys exist
CountTestCustomer.any!
#=> false

## size alias works correctly (aliases to fast count method)
@cust4 = CountTestCustomer.create!(custid: 'charlie', name: 'Charlie')
CountTestCustomer.size == CountTestCustomer.count
#=> true

## length alias works correctly (aliases to fast count method)
CountTestCustomer.length == CountTestCustomer.count
#=> true

# Cleanup
CountTestCustomer.instances.clear
CountTestCustomer.all.each(&:destroy!)
