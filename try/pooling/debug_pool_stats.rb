#!/usr/bin/env ruby
# Debug what pool stats are actually being recorded

require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

# Create a simple test scenario
puts "Creating test with 3 threads, 1 connection pool"

# First, let's see what happens with the pool during configuration
puts "\n=== Pool Configuration Debug ==="
puts "Before test creation:"
puts "  Familia pool size: #{Familia.connection_pool.size}"
puts "  Familia pool available: #{Familia.connection_pool.available}"

test = ConnectionPoolStressTest.new(
  thread_count: 3,
  operations_per_thread: 5,
  pool_size: 1,
  pool_timeout: 10,
  workload_size: :small
)

puts "\nAfter test creation:"
puts "  Familia pool size: #{Familia.connection_pool.size}"
puts "  Familia pool available: #{Familia.connection_pool.available}"
puts "  Test config pool_size: #{test.config[:pool_size]}"

# Let's look at the actual metrics being recorded
puts "\n=== Running Test ==="
test.run

# Examine the pool stats
pool_stats = test.metrics.pool_stats
puts "\n=== Pool Stats Analysis ==="
puts "Total samples: #{pool_stats.size}"

if pool_stats.any?
  # Group by unique configurations
  unique_configs = pool_stats.map { |s| "size=#{s[:size]}, available=#{s[:available]}" }.uniq
  puts "Unique pool states observed:"
  unique_configs.each { |config| puts "  #{config}" }

  # Show first and last few samples
  puts "\nFirst 5 samples:"
  pool_stats.first(5).each_with_index do |stat, i|
    puts "  #{i}: size=#{stat[:size]}, available=#{stat[:available]}, util=#{stat[:utilization]}%"
  end

  puts "\nLast 5 samples:"
  pool_stats.last(5).each_with_index do |stat, i|
    idx = pool_stats.size - 5 + i
    puts "  #{idx}: size=#{stat[:size]}, available=#{stat[:available]}, util=#{stat[:utilization]}%"
  end

  # Check if size matches config
  sizes = pool_stats.map { |s| s[:size] }.uniq
  puts "\nPool sizes observed: #{sizes.inspect}"
  puts "Expected pool size from config: #{test.config[:pool_size]}"

  # Calculate real utilization distribution
  utilizations = pool_stats.map { |s| s[:utilization] }
  util_counts = utilizations.group_by(&:itself).transform_values(&:count)
  puts "\nUtilization distribution:"
  util_counts.sort.each do |util, count|
    percentage = (count.to_f / pool_stats.size * 100).round(1)
    puts "  #{util}%: #{count} samples (#{percentage}%)"
  end
end

# Let's also check what the summary says vs reality
summary = test.metrics.summary
puts "\n=== Metrics Summary ==="
puts "Max pool utilization reported: #{summary[:max_pool_utilization]}%"
puts "Actual max from samples: #{pool_stats.map { |s| s[:utilization] }.max}%" if pool_stats.any?
