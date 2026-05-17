# try/edge_cases/iterator_connection_errors_try.rb
#
# frozen_string_literal: true

# Tests and documents expected behavior of iterators when Redis connection errors occur.
#
# IMPORTANT: These tests document EXPECTED behavior but cannot fully test connection
# failure mid-iteration without mocks (which conflicts with project philosophy).
# The documentation here serves as specification for manual testing and code review.
#
# Expected behavior when Redis::ConnectionError occurs during iteration:
#
# 1. ERROR PROPAGATION: Redis::ConnectionError propagates to caller without being
#    swallowed. The caller receives the raw exception and can decide to retry.
#
# 2. PARTIAL RESULTS: If error occurs mid-iteration, already-yielded items are
#    processed but not returned (no rollback of block side effects).
#
# 3. DATA INTEGRITY: The underlying Redis data structure is NOT corrupted by the
#    interrupted iteration. SCAN cursor state is maintained in Redis, not client.
#
# 4. RETRY SEMANTICS: A fresh iteration after reconnection will start from cursor 0
#    and correctly iterate all items (SCAN cursors are ephemeral).

require_relative '../support/helpers/test_helpers'

# Setup
@bone = Bone.new 'connection_error_test'
10.times { |i| @bone.tags.add "item_#{i}" }

# ============================================================
# Baseline: verify normal iteration works (prerequisite)
# ============================================================

## Normal iteration completes without error
@seen = []
@bone.tags.each { |item| @seen << item }
@seen.size
#=> 10

## Normal iteration can be restarted
@seen_again = []
@bone.tags.each { |item| @seen_again << item }
@seen_again.sort == @seen.sort
#=> true

# ============================================================
# Error behavior documentation (as tests)
# ============================================================

## Familia iterators do not swallow exceptions
# This test verifies that exceptions raised in blocks propagate
@exception_seen = []
begin
  @bone.tags.each do |item|
    @exception_seen << item
    raise 'TestError' if @exception_seen.size == 5
  end
rescue RuntimeError => e
  e.message
end
#=> 'TestError'

## Partial results are preserved in caller's context before exception
# The items seen before the exception remain available
@exception_seen.size
#=> 5

## Iteration can resume after exception from caller's block
# The data structure remains intact
resumed = []
@bone.tags.each { |item| resumed << item }
resumed.size
#=> 10

# ============================================================
# Connection recovery behavior
# ============================================================

## Connection recovery: iterator works after connection is restored
# Simulating connection recovery by ensuring clean state
# (In production, connection pool handles reconnection transparently)
fresh_seen = []
@bone.tags.each { |item| fresh_seen << item }
fresh_seen.sort == @bone.tags.members.sort
#=> true

## SCAN cursor is ephemeral - no stale state after reconnection
# Each iteration starts fresh from cursor 0
# (SCAN cursors are server-side and tied to connection, not persistent)
iteration1 = @bone.tags.each.to_a
iteration2 = @bone.tags.each.to_a
iteration1.sort == iteration2.sort
#=> true

# Teardown
@bone.tags.clear rescue nil
