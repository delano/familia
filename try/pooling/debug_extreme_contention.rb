#!/usr/bin/env ruby
# Debug script to understand pool monitoring with extreme contention

require_relative '../helpers/test_helpers'
require_relative 'lib/atomic_saves_v3_connection_pool_helpers'
require_relative 'lib/connection_pool_stress_test'

# Create a pool with only 1 connection
Familia.class_variable_set(:@@connection_pool, ConnectionPool.new(size: 1, timeout: 10) do
  Redis.new(url: Familia.uri.to_s)
end)

puts "Testing extreme contention: 10 threads, 1 connection"
puts "Pool size: #{Familia.connection_pool.size}"
puts "Initial available: #{Familia.connection_pool.available}\n\n"

# Track monitoring results
monitor_samples = []
monitor_running = true

# Monitor thread with more aggressive sampling
monitor = Thread.new do
  sample_count = 0
  while monitor_running
    available = Familia.connection_pool.available
    size = Familia.connection_pool.size
    util = ((size - available).to_f / size * 100).round(2)
    monitor_samples << { available: available, util: util, time: Time.now }
    sample_count += 1
    print "." if util > 0
    sleep 0.001  # Sample every 1ms
  end
  puts "\nMonitor took #{sample_count} samples"
end

# Create competing threads
threads = []
operation_times = []

10.times do |i|
  threads << Thread.new do
    account = BankAccount.new
    account.balance = 1000
    account.generate_metadata(:large)

    # Time the entire operation including wait time
    start = Time.now
    wait_start = start

    Familia.connection_pool.with do |conn|
      wait_time = Time.now - wait_start

      # Simulate the atomic operation
      op_start = Time.now
      Familia.current_transaction = conn
      begin
        account.save
      ensure
        Familia.current_transaction = nil
      end
      op_time = Time.now - op_start

      total_time = Time.now - start
      operation_times << {
        thread: i,
        wait: wait_time,
        operation: op_time,
        total: total_time
      }

      puts "Thread #{i}: wait=#{(wait_time*1000).round(1)}ms, op=#{(op_time*1000).round(1)}ms, total=#{(total_time*1000).round(1)}ms"
    end
  end
end

# Wait for all threads
threads.each(&:join)
monitor_running = false
monitor.join

# Analyze results
puts "\n=== Analysis ==="
puts "Total samples: #{monitor_samples.size}"
non_zero_samples = monitor_samples.select { |s| s[:util] > 0 }
puts "Non-zero utilization samples: #{non_zero_samples.size}"

if non_zero_samples.any?
  puts "Max utilization: #{non_zero_samples.map { |s| s[:util] }.max}%"
  puts "Average utilization: #{(non_zero_samples.map { |s| s[:util] }.sum / non_zero_samples.size).round(2)}%"
else
  puts "No utilization detected!"
end

# Check timing
total_test_time = monitor_samples.last[:time] - monitor_samples.first[:time]
puts "\nTest duration: #{(total_test_time * 1000).round(1)}ms"
puts "Average operation time: #{(operation_times.map { |t| t[:total] }.sum / operation_times.size * 1000).round(1)}ms"
puts "Average wait time: #{(operation_times.map { |t| t[:wait] }.sum / operation_times.size * 1000).round(1)}ms"

# Show a timeline sample
puts "\nSample timeline (first 20 samples):"
monitor_samples.first(20).each_with_index do |sample, i|
  puts "  #{i}: available=#{sample[:available]}, util=#{sample[:util]}%"
end
