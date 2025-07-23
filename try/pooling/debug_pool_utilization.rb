#!/usr/bin/env ruby
# Debug script to understand pool utilization

require_relative '../helpers/test_helpers'
require_relative 'lib/atomic_saves_v3_connection_pool_helpers'
require 'connection_pool'

# The atomic_saves_v3_connection_pool_helpers.rb already sets up a pool with size 10
# Let's just use that and observe its behavior

puts "Pool size: #{Familia.connection_pool.size}"
puts "Initial available: #{Familia.connection_pool.available}"
puts ""

# Test 1: Check pool during single checkout
puts "Test 1: Single checkout"
Familia.connection_pool.with do |conn|
  puts "  During checkout - Available: #{Familia.connection_pool.available}"
  puts "  Utilization: #{((Familia.connection_pool.size - Familia.connection_pool.available).to_f / Familia.connection_pool.size * 100).round(2)}%"
end
puts "  After checkout - Available: #{Familia.connection_pool.available}"
puts ""

# Test 2: Multiple concurrent checkouts
puts "Test 2: Multiple concurrent checkouts"
threads = []
3.times do |i|
  threads << Thread.new do
    Familia.connection_pool.with do |conn|
      puts "  Thread #{i} - Available: #{Familia.connection_pool.available}"
      sleep 0.1  # Hold connection briefly
    end
  end
end
sleep 0.05  # Let threads start
puts "  During multiple checkouts - Available: #{Familia.connection_pool.available}"
threads.each(&:join)
puts ""

# Test 3: Using Familia.atomic
puts "Test 3: During Familia.atomic"
account = BankAccount.new(account_number: "test123", balance: 1000)
Familia.atomic do
  puts "  Inside atomic - Available: #{Familia.connection_pool.available}"
  account.save
  puts "  After save - Available: #{Familia.connection_pool.available}"
end
puts "  After atomic - Available: #{Familia.connection_pool.available}"
puts ""

# Test 4: Monitor during rapid operations
puts "Test 4: Rapid operations monitoring"
utilizations = []
monitor = Thread.new do
  10.times do
    available = Familia.connection_pool.available
    size = Familia.connection_pool.size
    util = ((size - available).to_f / size * 100).round(2)
    utilizations << util
    sleep 0.001
  end
end

# Perform rapid operations
5.times do
  Familia.atomic do
    account = BankAccount.new
    account.save
  end
end

monitor.join
puts "  Utilizations observed: #{utilizations}"
puts "  Max utilization: #{utilizations.max}%"
puts "  Non-zero utilizations: #{utilizations.select { |u| u > 0 }}"
