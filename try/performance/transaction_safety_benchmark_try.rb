# try/performance/transaction_safety_benchmark_try.rb
#
# frozen_string_literal: true

# Transaction Safety Performance Benchmarks
#
# Measures the performance impact of transaction safety mechanisms
# and compares different transaction patterns for overhead analysis.
#

require_relative '../support/helpers/test_helpers'
require 'benchmark'

# Benchmark test model
class ::BenchmarkCustomer < Familia::Horreum
  identifier_field :customer_id
  field :customer_id
  field :login_count
  field :status
  field :balance

  list :orders
  set :tags
end

# Helper for generating test data
def benchmark_id(prefix = 'bench')
  "#{prefix}_#{Time.now.to_i}_#{rand(100000)}"
end

# Setup test customers
@customers = 100.times.map do |i|
  customer = BenchmarkCustomer.new(
    customer_id: benchmark_id("customer_#{i}"),
    login_count: 0,
    status: 'active',
    balance: 1000
  )
  customer.save
  customer
end

## Simple transaction performance baseline
@start_time = Time.now
@customers.first(10).each do |customer|
  customer.transaction do
    customer.hset(:login_count, '1')
    customer.hset(:status, 'updated')
  end
end
@simple_duration = ((Time.now - @start_time) * 1000).round(2)
@simple_duration < 100  # Should complete in under 100ms
#=> true

## Nested transaction performance (reentrant)
@start_time = Time.now
@customers[10, 10].each do |customer|
  customer.transaction do
    customer.hset(:login_count, '1')

    # Nested transaction (reentrant)
    customer.transaction do
      customer.hset(:status, 'nested_updated')
      customer.orders.push('nested_order')
    end

    customer.hset(:balance, '950')
  end
end
@nested_duration = ((Time.now - @start_time) * 1000).round(2)
@nested_duration < 150  # Should have minimal overhead
#=> true

## Nested vs simple transaction overhead ratio
@overhead_ratio = @nested_duration / @simple_duration
@overhead_ratio < 2.0  # Nested should be less than 2x slower
#=> true

## Bulk operations in single transaction
@start_time = Time.now
BenchmarkCustomer.transaction do |conn|
  @customers[20, 20].each do |customer|
    conn.hset(customer.dbkey, 'bulk_status', 'processed')
    conn.hset(customer.dbkey, 'bulk_timestamp', Time.now.to_i.to_s)
  end
end
@bulk_duration = ((Time.now - @start_time) * 1000).round(2)
@bulk_duration < 50  # Bulk should be faster per operation
#=> true

## Individual transactions vs bulk transaction efficiency
@individual_start = Time.now
@customers[40, 10].each do |customer|
  customer.transaction do
    customer.hset(:individual_status, 'processed')
  end
end
@individual_duration = ((Time.now - @individual_start) * 1000).round(2)

@bulk_per_op = @bulk_duration / 20
@individual_per_op = @individual_duration / 10
@efficiency_ratio = @individual_per_op / @bulk_per_op
@efficiency_ratio > 1.5  # Individual should be slower per operation
#=> true

## Connection reuse verification in nested transactions
@connection_ids = []
@customers[50, 1].each do |customer|
  customer.transaction do |outer_conn|
    @connection_ids << outer_conn.object_id

    customer.transaction do |inner_conn|
      @connection_ids << inner_conn.object_id
      customer.hset(:conn_test, 'value')
    end
  end
end

# Both connection IDs should be the same (reentrant)
@connection_ids.uniq.size == 1 && @connection_ids.size == 2
#=> true

## Memory usage with deep nesting
@deep_nesting_start = Time.now
@test_customer = @customers[60]

@result = @test_customer.transaction do
  @test_customer.hset(:level_1, 'value')

  @test_customer.transaction do
    @test_customer.hset(:level_2, 'value')

    @test_customer.transaction do
      @test_customer.hset(:level_3, 'value')

      @test_customer.transaction do
        @test_customer.hset(:level_4, 'value')
        @test_customer.orders.push('deep_order')
      end
    end
  end
end

@deep_nesting_duration = ((Time.now - @deep_nesting_start) * 1000).round(2)
@deep_nesting_duration < 50  # Even deep nesting should be fast
#=> true

## Error handling performance in transactions
@error_handling_start = Time.now
@error_count = 0

10.times do |i|
  customer = @customers[70 + i]
  begin
    customer.transaction do
      customer.hset(:test_field, 'value')
      raise 'simulated error' if i.even?
      customer.hset(:success_field, 'success')
    end
  rescue => e
    @error_count += 1
  end
end

@error_handling_duration = ((Time.now - @error_handling_start) * 1000).round(2)
@error_handling_duration < 100  # Error handling shouldn't be too slow
#=> true

## Correct number of errors caught
@error_count == 5  # Should catch 5 errors (even indices)
#=> true

## Fiber-local storage performance impact
@fiber_storage_start = Time.now

10.times do |i|
  customer = @customers[80 + i]
  customer.transaction do
    # Access fiber-local storage multiple times
    current_txn = Fiber[:familia_transaction]
    handler_class = Fiber[:familia_connection_handler_class]

    customer.hset(:fiber_test, "#{current_txn.class.name}_#{i}")
  end
end

@fiber_storage_duration = ((Time.now - @fiber_storage_start) * 1000).round(2)
@fiber_storage_duration < 75  # Fiber access should be fast
#=> true

## Transaction vs pipeline performance comparison
@transaction_start = Time.now
@customers[90, 5].each do |customer|
  customer.transaction do |conn|
    conn.hset(customer.dbkey, 'txn_field1', 'value1')
    conn.hset(customer.dbkey, 'txn_field2', 'value2')
    conn.hset(customer.dbkey, 'txn_field3', 'value3')
  end
end
@transaction_perf_duration = ((Time.now - @transaction_start) * 1000).round(2)

@pipeline_start = Time.now
@customers[95, 5].each do |customer|
  customer.dbclient.pipelined do |pipe|
    pipe.hset(customer.dbkey, 'pipe_field1', 'value1')
    pipe.hset(customer.dbkey, 'pipe_field2', 'value2')
    pipe.hset(customer.dbkey, 'pipe_field3', 'value3')
  end
end
@pipeline_perf_duration = ((Time.now - @pipeline_start) * 1000).round(2)

# Pipeline should be faster or comparable
@performance_difference = @transaction_perf_duration / @pipeline_perf_duration
@performance_difference < 3.0  # Transaction shouldn't be more than 3x slower
#=> true

## Benchmark summary shows acceptable performance
@benchmark_summary = {
  simple_transaction: @simple_duration,
  nested_transaction: @nested_duration,
  bulk_operations: @bulk_duration,
  error_handling: @error_handling_duration,
  fiber_storage: @fiber_storage_duration,
  transaction_vs_pipeline: @performance_difference
}

# All operations should complete reasonably quickly
@benchmark_summary.values.all? { |v| v < 200 }
#=> true

## Performance regression check - nested overhead
@nested_overhead_percent = ((@nested_duration - @simple_duration) / @simple_duration * 100).round(1)
@nested_overhead_percent < 100  # Less than 100% overhead (2x) - increased threshold for CI stability
#=> true

## Performance benchmark completed successfully
true
#=> true
