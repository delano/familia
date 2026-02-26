require_relative '../support/helpers/test_helpers'

# Test class for count/any edge case testing - synchronization issues
class EdgeCaseCustomer < Familia::Horreum
  identifier_field :custid
  field :custid
  field :name
end

# Setup - clear any existing data
EdgeCaseCustomer.instances.clear
# Clear all keys matching the pattern
EdgeCaseCustomer.dbclient.scan_each(match: EdgeCaseCustomer.dbkey('*')) do |key|
  EdgeCaseCustomer.dbclient.del(key)
end

# =============================================================================
# Edge Case 1: Phantom Instances (stale additions)
# Identifier exists in instances sorted set but object key doesn't exist
# =============================================================================

## EDGE: Phantom instance - count shows stale entry
# Manually add identifier to instances without creating object
EdgeCaseCustomer.instances.add('phantom1', Familia.now.to_i)
EdgeCaseCustomer.count
#=> 1

## EDGE: Phantom instance - keys_count shows authoritative count (0)
EdgeCaseCustomer.keys_count
#=> 0

## EDGE: Phantom instance - scan_count shows authoritative count (0)
EdgeCaseCustomer.scan_count
#=> 0

## EDGE: Phantom instance - count! shows authoritative count (0)
EdgeCaseCustomer.count!
#=> 0

## EDGE: Phantom instance - any? returns true (stale)
EdgeCaseCustomer.any?
#=> true

## EDGE: Phantom instance - keys_any? returns false (authoritative)
EdgeCaseCustomer.keys_any?
#=> false

## EDGE: Phantom instance - scan_any? returns false (authoritative)
EdgeCaseCustomer.scan_any?
#=> false

## EDGE: Phantom instance - any! returns false (authoritative)
EdgeCaseCustomer.any!
#=> false

## EDGE: Phantom instance cleanup - clear instances
EdgeCaseCustomer.instances.clear
#=*> Integer

# =============================================================================
# Edge Case 2: Orphaned Objects
# Object exists in Redis but identifier NOT in instances sorted set
# =============================================================================

## EDGE: Orphaned object - create and remove from instances manually
@orphan = EdgeCaseCustomer.create!(custid: 'orphan1', name: 'Orphan')
EdgeCaseCustomer.instances.remove('orphan1')
# After removal, count should be 0 but object still exists
EdgeCaseCustomer.count
#=> 0

## EDGE: Orphaned object - keys_count finds the orphan
EdgeCaseCustomer.keys_count
#=> 1

## EDGE: Orphaned object - scan_count finds the orphan
EdgeCaseCustomer.scan_count
#=> 1

## EDGE: Orphaned object - count! finds the orphan
EdgeCaseCustomer.count!
#=> 1

## EDGE: Orphaned object - any? returns false (no instances entry)
# Since instances is empty, any? should return false
EdgeCaseCustomer.any?
#=> false

## EDGE: Orphaned object - keys_any? returns true (object exists)
EdgeCaseCustomer.keys_any?
#=> true

## EDGE: Orphaned object - scan_any? returns true (object exists)
EdgeCaseCustomer.scan_any?
#=> true

## EDGE: Orphaned object - any! returns true (object exists)
EdgeCaseCustomer.any!
#=> true

## EDGE: Orphaned object cleanup - destroy and clear
@orphan.destroy!
EdgeCaseCustomer.instances.clear
EdgeCaseCustomer.all.each(&:destroy!)
#=*> Array

# =============================================================================
# Edge Case 3: Duplicate Instance Entries
# Same identifier added multiple times to instances (shouldn't happen but test it)
# =============================================================================

## EDGE: Duplicate entries - create fresh customer
@dup = EdgeCaseCustomer.create!(custid: 'dup1', name: 'Duplicate')
# Manually add the same identifier again with different score
# ZADD should just update the score, not create duplicate
EdgeCaseCustomer.instances.add('dup1', Familia.now.to_i + 1000)
EdgeCaseCustomer.count
#=> 1

## EDGE: Duplicate entries - keys_count also shows 1
EdgeCaseCustomer.keys_count
#=> 1

## EDGE: Duplicate entries - scan_count also shows 1
EdgeCaseCustomer.scan_count
#=> 1

## EDGE: Duplicate entries cleanup - destroy and clear
@dup.destroy!
EdgeCaseCustomer.instances.clear
EdgeCaseCustomer.all.each(&:destroy!)
#=*> Array

# =============================================================================
# Edge Case 4: Empty Identifier
# What happens with empty string identifier?
# =============================================================================

## EDGE: Empty identifier - instances can store empty string
EdgeCaseCustomer.instances.add('', Familia.now.to_i)
EdgeCaseCustomer.count
#=> 1

## EDGE: Empty identifier - keys_count returns 0 (no matching keys)
# Empty identifier doesn't create valid keys
EdgeCaseCustomer.keys_count
#=> 0

## EDGE: Empty identifier - scan_count returns 0 (no matching keys)
EdgeCaseCustomer.scan_count
#=> 0

## EDGE: Empty identifier cleanup - clear all
EdgeCaseCustomer.instances.clear
EdgeCaseCustomer.all.each(&:destroy!)
#=*> Array

# =============================================================================
# Edge Case 5: Mixed State - Multiple Desync Scenarios
# Combination of phantoms, orphans, and valid objects
# =============================================================================

## EDGE: Mixed state - setup complex scenario
@valid1 = EdgeCaseCustomer.create!(custid: 'valid1', name: 'Valid 1')
@valid2 = EdgeCaseCustomer.create!(custid: 'valid2', name: 'Valid 2')
# Create phantom (in instances but no object)
EdgeCaseCustomer.instances.add('phantom2', Familia.now.to_i)
# Create orphan (object but not in instances)
@orphan2 = EdgeCaseCustomer.create!(custid: 'orphan2', name: 'Orphan 2')
EdgeCaseCustomer.instances.remove('orphan2')
# instances has: valid1, valid2, phantom2 = 3
EdgeCaseCustomer.count
#=> 3

## EDGE: Mixed state - keys_count shows authoritative count
# Actual objects exist: valid1, valid2, orphan2 = 3
EdgeCaseCustomer.keys_count
#=> 3

## EDGE: Mixed state - scan_count shows authoritative count
EdgeCaseCustomer.scan_count
#=> 3

## EDGE: Mixed state - count! shows authoritative count
EdgeCaseCustomer.count!
#=> 3

## EDGE: Mixed state - both counts match in this case
# By coincidence, both are 3 (different reasons though)
EdgeCaseCustomer.keys_count == EdgeCaseCustomer.count
#=> true

## EDGE: Mixed state cleanup - clear all
EdgeCaseCustomer.instances.clear
EdgeCaseCustomer.all.each(&:destroy!)
#=*> Array

# =============================================================================
# Edge Case 6: Special Characters in Identifiers
# Unicode, special chars, patterns that might break filters
# =============================================================================

## EDGE: Special chars - asterisk in identifier
@special1 = EdgeCaseCustomer.create!(custid: 'user*123', name: 'Special')
EdgeCaseCustomer.count
#=> 1

## EDGE: Special chars - keys_count finds it
EdgeCaseCustomer.keys_count
#=> 1

## EDGE: Special chars - scan_count finds it
EdgeCaseCustomer.scan_count
#=> 1

## EDGE: Special chars - filter with asterisk pattern
# This tests if the literal asterisk in custid affects pattern matching
EdgeCaseCustomer.keys_count('user*')
#=> 1

## EDGE: Special chars - scan filter with asterisk pattern
EdgeCaseCustomer.scan_count('user*')
#=> 1

## EDGE: Special chars cleanup - destroy special1
@special1.destroy!
#=*> Integer

## EDGE: Special chars - question mark in identifier
@special2 = EdgeCaseCustomer.create!(custid: 'user?456', name: 'Special2')
EdgeCaseCustomer.keys_count('user?*')
#=> 1

## EDGE: Special chars - scan filter with question mark pattern
EdgeCaseCustomer.scan_count('user?*')
#=> 1

## EDGE: Special chars cleanup - destroy special2
@special2.destroy!
#=*> Integer

## EDGE: Special chars - brackets in identifier
@special3 = EdgeCaseCustomer.create!(custid: 'user[test]', name: 'Special3')
EdgeCaseCustomer.keys_count('user*')
#=> 1

## EDGE: Special chars - scan finds bracketed identifier
EdgeCaseCustomer.scan_count('user*')
#=> 1

## EDGE: Special chars cleanup - destroy special3 and clear
@special3.destroy!
EdgeCaseCustomer.instances.clear
#=*> Integer

# =============================================================================
# Edge Case 7: Score Manipulation
# Instances sorted set uses scores (timestamps), test score edge cases
# =============================================================================

## EDGE: Score manipulation - zero score
EdgeCaseCustomer.instances.add('score_test1', 0)
EdgeCaseCustomer.count
#=> 1

## EDGE: Score manipulation - negative score
EdgeCaseCustomer.instances.add('score_test2', -12345)
EdgeCaseCustomer.count
#=> 2

## EDGE: Score manipulation - very large score
EdgeCaseCustomer.instances.add('score_test3', 9999999999999)
EdgeCaseCustomer.count
#=> 3

## EDGE: Score manipulation - scores don't affect count
# Regardless of score values, count should be accurate
EdgeCaseCustomer.count
#=> 3

## EDGE: Score manipulation - keys_count ignores scores (checks actual keys)
EdgeCaseCustomer.keys_count
#=> 0

## EDGE: Score manipulation - scan_count ignores scores
EdgeCaseCustomer.scan_count
#=> 0

## EDGE: Score manipulation cleanup - clear instances
EdgeCaseCustomer.instances.clear
#=*> Integer

# =============================================================================
# Edge Case 8: Large Dataset - Scan Cursor Behavior
# Test that scan_count properly iterates through large datasets
# =============================================================================

## EDGE: Large dataset - create 100 instances
100.times do |i|
  EdgeCaseCustomer.create!(custid: "large#{i}", name: "Large #{i}")
end
EdgeCaseCustomer.count
#=> 100

## EDGE: Large dataset - keys_count matches (blocks but works)
EdgeCaseCustomer.keys_count
#=> 100

## EDGE: Large dataset - scan_count matches (non-blocking, cursor iteration)
EdgeCaseCustomer.scan_count
#=> 100

## EDGE: Large dataset - count! matches
EdgeCaseCustomer.count!
#=> 100

## EDGE: Large dataset - scan_any? returns true efficiently
EdgeCaseCustomer.scan_any?
#=> true

## EDGE: Large dataset - keys_any? returns true
EdgeCaseCustomer.keys_any?
#=> true

## EDGE: Large dataset - filter scan works with many results
EdgeCaseCustomer.scan_count('large1*')
#=> 11

## EDGE: Large dataset - filter keys works with many results
EdgeCaseCustomer.keys_count('large1*')
#=> 11

## EDGE: Large dataset cleanup - clear all
EdgeCaseCustomer.instances.clear
EdgeCaseCustomer.all.each(&:destroy!)
#=*> Array

# =============================================================================
# Edge Case 9: Manual Redis Operations Breaking Consistency
# Direct Redis commands that bypass Familia's tracking
# =============================================================================

## EDGE: Manual ops - RENAME breaks dbkey pattern
@manual1 = EdgeCaseCustomer.create!(custid: 'manual1', name: 'Manual')
original_key = @manual1.dbkey
EdgeCaseCustomer.dbclient.rename(original_key, 'some:random:key')
EdgeCaseCustomer.count
#=> 1

## EDGE: Manual ops - keys_count doesn't find renamed key
EdgeCaseCustomer.keys_count
#=> 0

## EDGE: Manual ops - scan_count doesn't find renamed key
EdgeCaseCustomer.scan_count
#=> 0

## EDGE: Manual ops - instances still has stale entry
EdgeCaseCustomer.any?
#=> true

## EDGE: Manual ops - but keys_any? correctly returns false
EdgeCaseCustomer.keys_any?
#=> false

## EDGE: Manual ops - and scan_any? correctly returns false
EdgeCaseCustomer.scan_any?
#=> false

## EDGE: Manual ops cleanup - delete renamed key and clear instances
EdgeCaseCustomer.dbclient.del('some:random:key')
EdgeCaseCustomer.instances.clear
#=*> Integer

# =============================================================================
# Edge Case 10: Partial Transaction Failures
# Simulate scenarios where object exists but instances tracking failed
# =============================================================================

## EDGE: Partial failure - manually create object without instances entry
@direct_key = EdgeCaseCustomer.new(custid: 'partial1', name: 'Partial').dbkey
EdgeCaseCustomer.dbclient.hset(@direct_key, 'custid', 'partial1')
EdgeCaseCustomer.dbclient.hset(@direct_key, 'name', 'Partial')
EdgeCaseCustomer.count
#=> 0

## EDGE: Partial failure - keys_count finds the manually created object
EdgeCaseCustomer.keys_count
#=> 1

## EDGE: Partial failure - scan_count finds it too
EdgeCaseCustomer.scan_count
#=> 1

## EDGE: Partial failure - count! finds it
EdgeCaseCustomer.count!
#=> 1

## EDGE: Partial failure - any? returns false (not in instances)
EdgeCaseCustomer.any?
#=> false

## EDGE: Partial failure - keys_any? returns true (key exists)
EdgeCaseCustomer.keys_any?
#=> true

## EDGE: Partial failure - scan_any? returns true (key exists)
EdgeCaseCustomer.scan_any?
#=> true

## EDGE: Partial failure cleanup - delete direct key and clear
EdgeCaseCustomer.dbclient.del(@direct_key)
EdgeCaseCustomer.instances.clear
#=*> Integer

# =============================================================================
# Edge Case 11: Filter Pattern Edge Cases
# Test filter behavior with complex patterns and edge cases
# =============================================================================

## EDGE: Filter patterns - create first filter test object
@filter1 = EdgeCaseCustomer.create!(custid: 'filter1', name: 'Filter1')
@filter1.custid
#=> 'filter1'

## EDGE: Filter patterns - single character wildcard
EdgeCaseCustomer.keys_count('?')
#=> 0

## EDGE: Filter patterns - create second filter test object
@filter2 = EdgeCaseCustomer.create!(custid: 'filter2', name: 'Filter2')
@filter2.custid
#=> 'filter2'

## EDGE: Filter patterns - multiple wildcards count
EdgeCaseCustomer.keys_count('*')
#=*> Integer

## EDGE: Filter patterns - scan with wildcard matches all
EdgeCaseCustomer.scan_count('*')
#=*> Integer

## EDGE: Filter patterns - range pattern
EdgeCaseCustomer.keys_count('filter[12]')
#=> 2

## EDGE: Filter patterns - scan with range pattern
EdgeCaseCustomer.scan_count('filter[12]')
#=> 2

## EDGE: Empty identifier cleanup - clear all
EdgeCaseCustomer.instances.clear
EdgeCaseCustomer.all.each(&:destroy!)
#=*> Array

# =============================================================================
# Edge Case 12: Boundary Conditions
# Test edge cases around zero, one, and boundary values
# =============================================================================

## EDGE: Boundary - scan_any? short-circuits on first match
# Create one object and verify scan_any? doesn't iterate unnecessarily
@boundary1 = EdgeCaseCustomer.create!(custid: 'boundary1', name: 'Boundary')
EdgeCaseCustomer.scan_any?
#=> true

## EDGE: Boundary - scan_any? with filter short-circuits
EdgeCaseCustomer.scan_any?('bound*')
#=> true

## EDGE: Boundary - scan_any? returns false when no matches
EdgeCaseCustomer.scan_any?('nonexistent*')
#=> false

## EDGE: Boundary - keys_any? with non-matching filter
EdgeCaseCustomer.keys_any?('nonexistent*')
#=> false

## EDGE: Boundary cleanup - destroy and clear
@boundary1.destroy!
EdgeCaseCustomer.instances.clear
#=*> Integer

## Final cleanup - clear instances
EdgeCaseCustomer.instances.clear
#=*> Integer
