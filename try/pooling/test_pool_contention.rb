#!/usr/bin/env ruby
# Test script to force pool contention and observe utilization

require_relative '../helpers/test_helpers'
require_relative 'lib/atomic_saves_v3_connection_pool_helpers'

# Create a small pool to force contention
Familia.class_variable_set(:@@connection_pool, ConnectionPool.new(size: 2, timeout: 5) do
  Redis.new(url: Familia.uri.to_s)
end)

puts "Pool size: #{Familia.connection_pool.size}"
puts "Starting pool contention test...\n"

# Track max utilization
max_utilization = 0
utilization_samples = []

# Monitor thread
monitor = Thread.new do
  50.times do
    available = Familia.connection_pool.available
    size = Familia.connection_pool.size
    util = ((size - available).to_f / size * 100).round(2)
    utilization_samples << util
    max_utilization = util if util > max_utilization
    sleep 0.01
  end
end

# Create threads that hold connections
threads = []
5.times do |i|
  threads << Thread.new do
    Familia.atomic do
      puts "Thread #{i} acquired connection (available: #{Familia.connection_pool.available})"

      # Hold connection for a bit
      sleep 0.2

      # Do some work
      account = BankAccount.new
      account.balance = 1000
      account.save

      puts "Thread #{i} releasing connection"
    end
  end
end

threads.each(&:join)
monitor.join

puts "\nResults:"
puts "Max pool utilization: #{max_utilization}%"
puts "Utilization samples: #{utilization_samples.select { |u| u > 0 }.sort.reverse.first(10)}"
puts "Average utilization: #{(utilization_samples.sum / utilization_samples.size).round(2)}%"
