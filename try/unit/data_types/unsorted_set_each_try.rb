# try/unit/data_types/unsorted_set_each_try.rb
#
# frozen_string_literal: true

# Tests for UnsortedSet#each with matching: filter.
# The matching: filter uses Redis SSCAN MATCH, which operates on raw storage
# (JSON-encoded strings). Values like "feature_auth" are stored as "\"feature_auth\"".
#
# NOTE: Patterns must account for JSON encoding. Use substring patterns like
# "*feature*" or explicit quote patterns like "\"feature_*" to match.
# For filtering on deserialized values, use Enumerable#select instead.

require_relative '../../support/helpers/test_helpers'

# Setup: Create test unsorted set with various member patterns
@bone = Bone.new 'unsorted_set_each_test'

# Populate with members that have different prefixes
@bone.tags.add 'feature_auth'
@bone.tags.add 'feature_billing'
@bone.tags.add 'feature_reports'
@bone.tags.add 'bug_login'
@bone.tags.add 'bug_timeout'
@bone.tags.add 'task_deploy'
@bone.tags.add 'task_review'

# Setup empty set for edge case tests
@empty_bone = Bone.new 'unsorted_set_each_empty_test'

# ============================================================
# Basic iteration
# ============================================================

## UnsortedSet#each without filters yields all members
collected = []
@bone.tags.each { |m| collected << m }
collected.sort
#=> ['bug_login', 'bug_timeout', 'feature_auth', 'feature_billing', 'feature_reports', 'task_deploy', 'task_review']

## UnsortedSet#each returns Enumerator when no block given
result = @bone.tags.each
result.class
#=> Enumerator

## UnsortedSet#each Enumerator yields member strings
first_member = @bone.tags.each.first
first_member.is_a?(String)
#=> true

## UnsortedSet#each counts all members
count = 0
@bone.tags.each { |_| count += 1 }
count
#=> 7

# ============================================================
# matching: filter with Redis MATCH patterns
# NOTE: Patterns match raw Redis storage (JSON-encoded strings)
# Values are stored as "\"value\"" so use substring patterns
# ============================================================

## UnsortedSet#each(matching:) filters by substring pattern
collected = []
@bone.tags.each(matching: '*feature*') { |m| collected << m }
collected.sort
#=> ['feature_auth', 'feature_billing', 'feature_reports']

## UnsortedSet#each(matching:) with bug substring
collected = []
@bone.tags.each(matching: '*bug*') { |m| collected << m }
collected.sort
#=> ['bug_login', 'bug_timeout']

## UnsortedSet#each(matching:) with task substring
collected = []
@bone.tags.each(matching: '*task*') { |m| collected << m }
collected.sort
#=> ['task_deploy', 'task_review']

## UnsortedSet#each(matching:) with suffix pattern
collected = []
@bone.tags.each(matching: '*_auth*') { |m| collected << m }
collected
#=> ['feature_auth']

## UnsortedSet#each(matching:) with wildcard matches all
collected = []
@bone.tags.each(matching: '*') { |m| collected << m }
collected.size
#=> 7

# ============================================================
# Empty result scenarios
# ============================================================

## UnsortedSet#each(matching:) with non-matching pattern returns empty
collected = []
@bone.tags.each(matching: '*nonexistent*') { |m| collected << m }
collected
#=> []

## UnsortedSet#each on empty set returns empty
collected = []
@empty_bone.tags.each { |m| collected << m }
collected
#=> []

## UnsortedSet#each with matching on empty set returns empty
collected = []
@empty_bone.tags.each(matching: '*') { |m| collected << m }
collected
#=> []

# ============================================================
# Batch size variations
# ============================================================

## UnsortedSet#each with batch_size smaller than member count
collected = []
@bone.tags.each(batch_size: 2) { |m| collected << m }
collected.size
#=> 7

## UnsortedSet#each with batch_size larger than member count
collected = []
@bone.tags.each(batch_size: 100) { |m| collected << m }
collected.size
#=> 7

## UnsortedSet#each with batch_size equal to member count
collected = []
@bone.tags.each(batch_size: 7) { |m| collected << m }
collected.size
#=> 7

## UnsortedSet#each with batch_size of 1 (extreme case)
collected = []
@bone.tags.each(batch_size: 1) { |m| collected << m }
collected.size
#=> 7

# ============================================================
# Combined filters and batch size
# ============================================================

## UnsortedSet#each with matching and batch_size
collected = []
@bone.tags.each(matching: '*feature*', batch_size: 2) { |m| collected << m }
collected.sort
#=> ['feature_auth', 'feature_billing', 'feature_reports']

## UnsortedSet#each with matching and small batch_size
collected = []
@bone.tags.each(matching: '*bug*', batch_size: 1) { |m| collected << m }
collected.sort
#=> ['bug_login', 'bug_timeout']

# ============================================================
# Edge cases and Enumerable integration
# ============================================================

## UnsortedSet#each combined with Enumerable#select for deserialized filtering
result = @bone.tags.each.select { |m| m.start_with?('task_') }
result.sort
#=> ['task_deploy', 'task_review']

## UnsortedSet#each allows mapping over filtered results
result = @bone.tags.each(matching: '*bug*').map(&:upcase)
result.sort
#=> ['BUG_LOGIN', 'BUG_TIMEOUT']

## UnsortedSet#each can be chained with take
result = @bone.tags.each.take(3).sort
result.size
#=> 3

## UnsortedSet#each with exact substring match
collected = []
@bone.tags.each(matching: '*task_deploy*') { |m| collected << m }
collected
#=> ['task_deploy']

# Teardown: Clean up test data
@bone.tags.delete!
@empty_bone.tags.delete!
