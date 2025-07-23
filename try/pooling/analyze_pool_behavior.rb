#!/usr/bin/env ruby
# Analyze pool behavior under different conditions

require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

def run_scenario(name, threads, pool_size, ops, workload)
  puts "\n=== #{name} ==="
  puts "Config: #{threads} threads, #{pool_size} pool, #{ops} ops/thread, #{workload} workload"

  test = ConnectionPoolStressTest.new(
    thread_count: threads,
    operations_per_thread: ops,
    pool_size: pool_size,
    pool_timeout: 10,
    workload_size: workload,
    scenario: :mixed_workload
  )

  # Verify pool was configured
  actual_pool_size = Familia.connection_pool.size
  puts "Actual pool size after config: #{actual_pool_size}"

  # Run test
  test.run

  # Analyze results
  pool_stats = test.metrics.pool_stats
  summary = test.metrics.summary

  if pool_stats.any?
    # Calculate real statistics
    utilizations = pool_stats.map { |s| s[:utilization] }
    non_zero = utilizations.select { |u| u > 0 }

    puts "\nResults:"
    puts "  Total samples: #{pool_stats.size}"
    puts "  Samples with utilization > 0: #{non_zero.size} (#{(non_zero.size.to_f / pool_stats.size * 100).round(1)}%)"
    puts "  Max utilization: #{utilizations.max}%"
    puts "  Average utilization: #{(utilizations.sum / utilizations.size).round(2)}%"
    puts "  Average when > 0: #{non_zero.any? ? (non_zero.sum / non_zero.size).round(2) : 0}%"

    # Check pool size consistency
    sizes = pool_stats.map { |s| s[:size] }.uniq
    if sizes.size > 1
      puts "  WARNING: Multiple pool sizes observed: #{sizes.inspect}"
    end

    # Show utilization histogram
    buckets = Hash.new(0)
    utilizations.each { |u| buckets[(u / 10).floor * 10] += 1 }

    puts "\n  Utilization histogram:"
    (0..100).step(10) do |bucket|
      count = buckets[bucket]
      if count > 0
        bar = "#" * [(count * 30 / pool_stats.size), 1].max
        puts "    #{bucket.to_s.rjust(3)}%: #{bar} (#{count})"
      end
    end
  else
    puts "\nNo pool stats recorded!"
  end

  puts "\nSummary reports: max_pool_utilization = #{summary[:max_pool_utilization]}%"
end

# Run different scenarios
run_scenario("Light load", 5, 5, 10, :small)
run_scenario("Moderate contention", 10, 5, 20, :medium)
run_scenario("High contention", 20, 2, 30, :large)
run_scenario("Extreme contention", 50, 1, 50, :large)

# Final test: Check if pool is being reset between tests
puts "\n=== Final Pool State ==="
puts "Pool size: #{Familia.connection_pool.size}"
puts "Available: #{Familia.connection_pool.available}"
