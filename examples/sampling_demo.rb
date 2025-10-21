#!/usr/bin/env ruby
# frozen_string_literal: true

# Demonstrates DatabaseLogger sampling to reduce log volume in high-traffic scenarios.
#
# Run with: bundle exec ruby examples/sampling_demo.rb

require_relative '../lib/familia'
require 'logger'

# Enable logging to see the effect
DatabaseLogger.logger = Logger.new($stdout)
DatabaseLogger.logger.level = Logger::TRACE

# Scenario 1: No sampling (default) - logs every command
puts "\n=== Scenario 1: No Sampling (logs all 100 commands) ==="
DatabaseLogger.sample_rate = nil
100.times { |i| Familia.dbclient.set("key_#{i}", "value_#{i}") }
puts "Commands captured: #{DatabaseLogger.commands.size}"
puts "(Check output above - should see ~100 log lines)"

# Scenario 2: 10% sampling - logs ~10 commands
puts "\n=== Scenario 2: 10% Sampling (logs ~10 of 100 commands) ==="
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = 0.1
100.times { |i| Familia.dbclient.set("sampled_10_#{i}", "value_#{i}") }
puts "Commands captured: #{DatabaseLogger.commands.size}"
puts "(Check output above - should see ~10 log lines)"

# Scenario 3: 1% sampling - logs ~1 command (production-friendly)
puts "\n=== Scenario 3: 1% Sampling (logs ~1 of 100 commands) ==="
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = 0.01
100.times { |i| Familia.dbclient.set("sampled_1_#{i}", "value_#{i}") }
puts "Commands captured: #{DatabaseLogger.commands.size}"
puts "(Check output above - should see ~1 log line)"

# Scenario 4: Sampling with structured logging
puts "\n=== Scenario 4: 10% Sampling + Structured Logging ==="
DatabaseLogger.clear_commands
DatabaseLogger.sample_rate = 0.1
DatabaseLogger.structured_logging = true
100.times { |i| Familia.dbclient.set("structured_#{i}", "value_#{i}") }
puts "Commands captured: #{DatabaseLogger.commands.size}"
puts "(Check structured output above)"

puts "\n=== Key Insights ==="
puts "✓ Command capture is unaffected (always 100 commands captured)"
puts "✓ Only logger output is sampled (reduces log volume)"
puts "✓ Tests can verify commands while production logs stay clean"
puts "✓ Deterministic sampling (every Nth command) ensures consistency"
