#!/usr/bin/env ruby
# Test to gather detailed utilization statistics

require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

# Test configuration
threads = 50
pool_size = 2
operations = 100
workload = :large

puts "Testing utilization with #{threads} threads, #{pool_size} connections, #{workload} workload"
puts "Total operations: #{threads * operations}\n\n"

# Create test
test = ConnectionPoolStressTest.new(
  thread_count: threads,
  operations_per_thread: operations,
  pool_size: pool_size,
  pool_timeout: 10,
  workload_size: workload,
  scenario: :mixed_workload
)

# Run test
test.run

# Get detailed stats
pool_stats = test.metrics.pool_stats
puts "\n=== Detailed Pool Utilization Stats ==="
puts "Total samples: #{pool_stats.size}"

if pool_stats.any?
  # Calculate utilization distribution
  utilization_buckets = Hash.new(0)
  pool_stats.each do |stat|
    bucket = (stat[:utilization] / 10).floor * 10  # Round down to nearest 10%
    utilization_buckets[bucket] += 1
  end

  puts "\nUtilization distribution:"
  (0..100).step(10) do |bucket|
    count = utilization_buckets[bucket]
    percentage = (count.to_f / pool_stats.size * 100).round(1)
    bar = "#" * (percentage / 2).to_i
    puts "  #{bucket.to_s.rjust(3)}%: #{bar.ljust(50)} #{percentage}% (#{count} samples)"
  end

  # Time analysis
  total_time = pool_stats.last[:timestamp] - pool_stats.first[:timestamp]
  puts "\nTime analysis:"
  puts "  Test duration: #{(total_time * 1000).round(1)}ms"
  puts "  Sampling rate: #{(pool_stats.size / total_time).round(1)} samples/sec"

  # Contention analysis
  non_zero = pool_stats.select { |s| s[:utilization] > 0 }
  if non_zero.any?
    puts "\nContention detected:"
    puts "  Samples with contention: #{non_zero.size} (#{(non_zero.size.to_f / pool_stats.size * 100).round(1)}%)"
    puts "  Average utilization when contended: #{(non_zero.map { |s| s[:utilization] }.sum / non_zero.size).round(1)}%"

    # Find longest contention period
    contention_periods = []
    current_period = nil

    pool_stats.each_with_index do |stat, i|
      if stat[:utilization] > 0
        if current_period.nil?
          current_period = { start: i, end: i, max_util: stat[:utilization] }
        else
          current_period[:end] = i
          current_period[:max_util] = [current_period[:max_util], stat[:utilization]].max
        end
      elsif current_period
        contention_periods << current_period
        current_period = nil
      end
    end
    contention_periods << current_period if current_period

    if contention_periods.any?
      longest = contention_periods.max_by { |p| p[:end] - p[:start] }
      duration = (pool_stats[longest[:end]][:timestamp] - pool_stats[longest[:start]][:timestamp]) * 1000
      puts "\n  Longest contention period: #{duration.round(1)}ms with #{longest[:max_util]}% max utilization"
      puts "  Number of contention periods: #{contention_periods.size}"
    end
  else
    puts "\nNo contention detected!"
  end
end
