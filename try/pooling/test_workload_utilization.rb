#!/usr/bin/env ruby
# Test script to debug pool utilization with workloads

require_relative '../helpers/test_helpers'
require_relative 'lib/connection_pool_stress_test'

# Create small pool
Familia.class_variable_set(:@@connection_pool, ConnectionPool.new(size: 2, timeout: 5) do
  Redis.new(url: Familia.uri.to_s)
end)

puts "Testing pool utilization with different workload sizes"
puts "Pool size: #{Familia.connection_pool.size}\n\n"

# Test each workload size
[:tiny, :small, :medium, :large].each do |workload_size|
  puts "=== Testing #{workload_size} workload ==="

  utilizations = []
  max_util = 0

  # Monitor thread
  monitor = Thread.new do
    20.times do
      available = Familia.connection_pool.available
      size = Familia.connection_pool.size
      util = ((size - available).to_f / size * 100).round(2)
      utilizations << util
      max_util = util if util > max_util
      print "." if util > 0  # Visual indicator when pool is in use
      sleep 0.005
    end
  end

  # Worker threads
  threads = []
  3.times do |i|
    threads << Thread.new do
      account = BankAccount.new
      account.balance = 1000
      account.generate_metadata(workload_size)

      # Measure operation time
      start = Time.now
      Familia.atomic do
        account.save
      end
      duration = Time.now - start

      puts "\n  Thread #{i}: Operation took #{(duration * 1000).round(2)}ms"
    end
  end

  threads.each(&:join)
  monitor.join

  puts "\n  Max utilization: #{max_util}%"
  puts "  Non-zero samples: #{utilizations.select { |u| u > 0 }.size}/#{utilizations.size}"
  puts ""
end
