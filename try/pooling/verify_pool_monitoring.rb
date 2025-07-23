#!/usr/bin/env ruby
# Verify pool monitoring is actually measuring real usage

require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

# Create a small pool
Familia.class_variable_set(:@@connection_pool, ConnectionPool.new(size: 3, timeout: 10) do
  Redis.new(url: Familia.uri.to_s)
end)

puts "Testing pool monitoring accuracy"
puts "Pool size: #{Familia.connection_pool.size}"
puts "Initial available: #{Familia.connection_pool.available}\n\n"

# Test 1: No activity - should show 0% utilization
puts "Test 1: No activity"
samples = []
5.times do
  available = Familia.connection_pool.available
  size = Familia.connection_pool.size
  util = ((size - available).to_f / size * 100).round(2)
  samples << util
  puts "  Available: #{available}/#{size}, Utilization: #{util}%"
  sleep 0.1
end
puts "  Average utilization: #{(samples.sum / samples.size).round(2)}%\n\n"

# Test 2: Hold connections manually
puts "Test 2: Manually holding connections"
connections = []
samples = []

# Check out connections one by one
3.times do |i|
  connections << Familia.connection_pool.checkout
  available = Familia.connection_pool.available
  size = Familia.connection_pool.size
  util = ((size - available).to_f / size * 100).round(2)
  samples << util
  puts "  Checked out #{i+1} connection(s): Available: #{available}/#{size}, Utilization: #{util}%"
end

# Return connections
connections.each_with_index do |conn, i|
  Familia.connection_pool.checkin(conn)
  available = Familia.connection_pool.available
  size = Familia.connection_pool.size
  util = ((size - available).to_f / size * 100).round(2)
  puts "  Returned #{i+1} connection(s): Available: #{available}/#{size}, Utilization: #{util}%"
end

puts "\nTest 3: Real workload monitoring"
# Create a test that actually uses the pool
test = ConnectionPoolStressTest.new(
  thread_count: 5,
  operations_per_thread: 20,
  pool_size: 2,  # Different from actual pool!
  pool_timeout: 10,
  workload_size: :small
)

puts "Configured pool_size in test: #{test.config[:pool_size]}"
puts "Actual pool size: #{Familia.connection_pool.size}"
puts "\nRunning test..."

# Run just the monitoring part
monitor_samples = []
monitor_thread = Thread.new do
  20.times do
    if Familia.connection_pool.respond_to?(:available)
      available = Familia.connection_pool.available
      size = Familia.connection_pool.size
      monitor_samples << {
        available: available,
        size: size,
        utilization: ((size - available).to_f / size * 100).round(2)
      }
    end
    sleep 0.01
  end
end

# Do some work
5.times do
  Thread.new do
    Familia.connection_pool.with do |conn|
      sleep 0.05  # Hold connection briefly
    end
  end
end

monitor_thread.join

puts "\nMonitor samples:"
monitor_samples.each_with_index do |sample, i|
  puts "  #{i}: size=#{sample[:size]}, available=#{sample[:available]}, util=#{sample[:utilization]}%"
end

max_util = monitor_samples.map { |s| s[:utilization] }.max
puts "\nMax utilization observed: #{max_util}%"
