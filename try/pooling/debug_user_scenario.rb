#!/usr/bin/env ruby
# Debug script for user's exact scenario

require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

# Exact user configuration
config = {
  thread_count: 100,
  operations_per_thread: 100,
  pool_size: 1,
  pool_timeout: 10,
  fresh_records: true,
  workload_size: :large,
  scenario: :mixed_workload
}

puts "Running user's exact scenario..."
puts "Expected: 100 threads competing for 1 connection should show high utilization\n\n"

# Create and run test
test = ConnectionPoolStressTest.new(config)

# Monkey patch to add debug output
original_record = test.metrics.method(:record_pool_stats)
samples_count = 0
test.metrics.define_singleton_method(:record_pool_stats) do |available, size|
  result = original_record.call(available, size)
  samples_count += 1
  if samples_count % 100 == 0  # Print every 100th sample
    util = ((size - available).to_f / size * 100).round(2)
    puts "Sample #{samples_count}: pool_size=#{size}, available=#{available}, utilization=#{util}%"
  end
  result
end

# Run the test
test.run

# Additional analysis
pool_stats = test.metrics.pool_stats
puts "\n=== Debug Analysis ==="
puts "Total monitor samples: #{pool_stats.size}"

# Check pool size consistency
pool_sizes = pool_stats.map { |s| s[:size] }.uniq
puts "Observed pool sizes: #{pool_sizes.inspect}"

# Check actual utilization values
utils = pool_stats.map { |s| s[:utilization] }.uniq.sort
puts "Unique utilization values: #{utils.inspect}"

# Sample some actual stats
puts "\nSample of actual stats:"
pool_stats.sample(5).each do |stat|
  puts "  Available: #{stat[:available]}, Size: #{stat[:size]}, Utilization: #{stat[:utilization]}%"
end
