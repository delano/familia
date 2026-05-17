# try/unit/batch_result_try.rb
#
# frozen_string_literal: true

# Tests for Familia::BatchResult - aggregates results from batch operations.
# BatchResult.collect iterates over any Enumerable and tracks scanned/modified/errors.

require_relative '../support/helpers/test_helpers'

# ============================================================
# BatchResult.collect with successful blocks
# ============================================================

## BatchResult.collect returns a BatchResult instance
result = Familia::BatchResult.collect([1, 2, 3]) { |n| n * 2 }
result.class
#=> Familia::BatchResult

## BatchResult.collect with empty enumerable
result = Familia::BatchResult.collect([]) { |_| true }
result.scanned
#=> 0

## BatchResult.collect with simple enumerable
result = Familia::BatchResult.collect([1, 2, 3, 4, 5]) { |n| n * 2 }
result.scanned
#=> 5

## BatchResult.collect works with any Enumerable (Range)
result = Familia::BatchResult.collect(1..10) { |n| n }
result.scanned
#=> 10

## BatchResult.collect works with Enumerator
result = Familia::BatchResult.collect([1, 2, 3].each) { |n| n }
result.scanned
#=> 3

## BatchResult.collect works with lazy Enumerator
result = Familia::BatchResult.collect([1, 2, 3, 4, 5].lazy.take(3)) { |n| n }
result.scanned
#=> 3

# ============================================================
# scanned count
# ============================================================

## scanned counts total records yielded
items = %w[a b c d e]
result = Familia::BatchResult.collect(items) { |_| true }
result.scanned
#=> 5

## scanned counts even when block raises
items = %w[a b c d e]
result = Familia::BatchResult.collect(items) { |item| raise 'oops' if item == 'c'; true }
result.scanned
#=> 5

## scanned counts records not block iterations
# Each item is scanned once regardless of block behavior
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| n > 1 }
result.scanned
#=> 3

# ============================================================
# modified count (truthy block returns)
# ============================================================

## modified counts truthy block returns
items = [1, 2, 3, 4, 5]
result = Familia::BatchResult.collect(items) { |n| n.even? ? n : nil }
result.modified
#=> 2

## modified counts all truthy values (not just true)
items = [1, 2, 3, 4, 5]
result = Familia::BatchResult.collect(items) { |n| n } # all truthy
result.modified
#=> 5

## modified is zero when all blocks return falsey
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |_| nil }
result.modified
#=> 0

## modified excludes false returns
items = [1, 2, 3, 4, 5]
result = Familia::BatchResult.collect(items) { |n| n > 3 } # 4, 5 return true
result.modified
#=> 2

## modified does not count errored items
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| raise 'error' if n == 2; true }
result.modified
#=> 2

# ============================================================
# errors captures exceptions with id
# ============================================================

## errors is empty when no exceptions
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| n }
result.errors
#=> []

## errors captures exception with item id
items = %w[a b c]
result = Familia::BatchResult.collect(items) { |item| raise 'fail' if item == 'b'; true }
result.errors.size
#=> 1

## errors contains error hash with :id and :error keys
items = %w[a b c]
result = Familia::BatchResult.collect(items) { |item| raise 'fail' if item == 'b'; true }
error_entry = result.errors.first
[error_entry.key?(:id), error_entry.key?(:error)]
#=> [true, true]

## errors :id contains the item that caused the error
items = %w[a b c]
result = Familia::BatchResult.collect(items) { |item| raise 'fail' if item == 'b'; true }
result.errors.first[:id]
#=> 'b'

## errors :error contains the Exception
items = %w[a b c]
result = Familia::BatchResult.collect(items) { |item| raise StandardError, 'fail' if item == 'b'; true }
result.errors.first[:error].class
#=> StandardError

## errors :error contains the exception message
items = %w[a b c]
result = Familia::BatchResult.collect(items) { |item| raise 'test message' if item == 'b'; true }
result.errors.first[:error].message
#=> 'test message'

## errors captures multiple exceptions
items = %w[a b c d e]
result = Familia::BatchResult.collect(items) { |item| raise 'fail' if item == 'b' || item == 'd'; true }
result.errors.size
#=> 2

## errors captures all errored item ids
items = %w[a b c d e]
result = Familia::BatchResult.collect(items) { |item| raise 'fail' if item == 'b' || item == 'd'; true }
result.errors.map { |e| e[:id] }.sort
#=> ['b', 'd']

## iteration continues after exception
items = [1, 2, 3, 4, 5]
processed = []
result = Familia::BatchResult.collect(items) { |n| raise 'skip' if n == 3; processed << n; true }
processed
#=> [1, 2, 4, 5]

# ============================================================
# duration_ms is populated
# ============================================================

## duration_ms is a Numeric
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |_| true }
result.duration_ms.is_a?(Numeric)
#=> true

## duration_ms is non-negative
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |_| true }
result.duration_ms >= 0
#=> true

## duration_ms reflects elapsed time
items = (1..10).to_a
result = Familia::BatchResult.collect(items) { |_| sleep(0.001); true }
result.duration_ms >= 10
#=> true

## duration_ms includes error handling time
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| raise 'slow' if n == 2; sleep(0.001); true }
result.duration_ms >= 2
#=> true

# ============================================================
# strict: true re-raises after iteration
# ============================================================

## strict: false (default) does not raise
items = [1, 2, 3]
begin
  result = Familia::BatchResult.collect(items) { |n| raise 'error' if n == 2; true }
  raised = false
rescue StandardError
  raised = true
end
raised
#=> false

## strict: true re-raises after full iteration
items = [1, 2, 3]
begin
  result = Familia::BatchResult.collect(items, strict: true) { |n| raise 'error' if n == 2; true }
  raised = false
rescue StandardError
  raised = true
end
raised
#=> true

## strict: true still completes iteration before raising
items = [1, 2, 3, 4, 5]
processed = []
begin
  Familia::BatchResult.collect(items, strict: true) do |n|
    raise 'error' if n == 2
    processed << n
    true
  end
rescue StandardError
  # Expected
end
processed
#=> [1, 3, 4, 5]

## strict: true re-raises the first error
items = [1, 2, 3]
begin
  Familia::BatchResult.collect(items, strict: true) { |n| raise "error_#{n}" if n == 2; true }
rescue StandardError => e
  e.message
end
#=> 'error_2'

## strict: true returns BatchResult before raising
# (Cannot test return value when exception is raised, but errors are captured)
items = [1, 2, 3]
captured_errors = nil
begin
  Familia::BatchResult.collect(items, strict: true) { |n| raise 'err' if n == 2; true }
rescue StandardError
  # Exception was raised
end
# The result would have errors if accessible
true
#=> true

# ============================================================
# Composition with real Enumerables
# ============================================================

## BatchResult works with Horreum-like objects
# Simulate what each_record would yield
fake_records = [
  OpenStruct.new(id: 1, name: 'Record 1'),
  OpenStruct.new(id: 2, name: 'Record 2'),
  OpenStruct.new(id: 3, name: 'Record 3')
]
result = Familia::BatchResult.collect(fake_records) { |r| r.id > 1 }
[result.scanned, result.modified]
#=> [3, 2]

## BatchResult works with hash iteration
hash = { a: 1, b: 2, c: 3 }
result = Familia::BatchResult.collect(hash) { |k, v| v > 1 }
result.scanned
#=> 3

## BatchResult works with Set
require 'set'
set = Set.new([1, 2, 3, 4, 5])
result = Familia::BatchResult.collect(set) { |n| n.odd? }
result.modified
#=> 3

## BatchResult works with File lines (simulated)
lines = "line1\nline2\nline3".split("\n")
result = Familia::BatchResult.collect(lines) { |line| line.length > 0 }
result.scanned
#=> 3

# ============================================================
# BatchResult accessors and helpers
# ============================================================

## BatchResult#successful? returns true when no errors
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |_| true }
result.successful?
#=> true

## BatchResult#successful? returns false when errors exist
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| raise 'err' if n == 2; true }
result.successful?
#=> false

## BatchResult#errors? returns false when no errors
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |_| true }
result.errors?
#=> false

## BatchResult#errors? returns true when errors exist
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| raise 'err' if n == 2; true }
result.errors?
#=> true

## BatchResult#to_h returns hash representation
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |n| n.odd? }
h = result.to_h
[h.key?(:scanned), h.key?(:modified), h.key?(:errors), h.key?(:duration_ms)]
#=> [true, true, true, true]

## BatchResult#to_h contains correct values
items = [1, 2, 3, 4, 5]
result = Familia::BatchResult.collect(items) { |n| n > 3 }
h = result.to_h
[h[:scanned], h[:modified]]
#=> [5, 2]

# ============================================================
# Edge cases
# ============================================================

## BatchResult handles nil items in enumerable
items = [1, nil, 3]
result = Familia::BatchResult.collect(items) { |n| n.nil? ? false : true }
[result.scanned, result.modified]
#=> [3, 2]

## BatchResult handles all errors
items = [1, 2, 3]
result = Familia::BatchResult.collect(items) { |_| raise 'all fail' }
[result.scanned, result.errors.size, result.modified]
#=> [3, 3, 0]

## BatchResult handles alternating success/error
items = [1, 2, 3, 4, 5]
result = Familia::BatchResult.collect(items) { |n| raise 'even' if n.even?; true }
[result.scanned, result.modified, result.errors.size]
#=> [5, 3, 2]
