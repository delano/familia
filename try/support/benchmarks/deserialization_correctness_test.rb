#!/usr/bin/env ruby
# try/support/benchmarks/deserialization_correctness_test.rb
#
# frozen_string_literal: true

# Correctness Test: Field deserialization strategies
# Verifies that different deserialization approaches produce identical
# results for all field types (strings, numbers, JSON, nested structures).
#
# Usage:
#   $ try/support/benchmarks/deserialization_correctness_test.rb
#

require_relative '../../../lib/familia'
require 'json'

# Setup Redis connection
Familia.uri = ENV['REDIS_URI'] || 'redis://localhost:2525/3'

# Sample model with various field types
class CorrectnessTestUser < Familia::Horreum
  identifier_field :user_id

  field :user_id
  field :name
  field :email
  field :age
  field :active
  field :metadata     # Will store JSON hash
  field :tags         # Will store JSON array
  field :created_at   # Will store timestamp
  field :score        # Will store float
  field :simple_string
  field :nested_data  # Will store deeply nested JSON
  field :empty_string
  field :nil_value
end

# Create sample data with comprehensive test cases
sample_data = {
  'user_id' => 'user_12345',
  'name' => 'John Doe',
  'email' => 'john.doe@example.com',
  'age' => '35',
  'active' => 'true',
  'metadata' => '{"role":"admin","department":"engineering","level":5}',
  'tags' => '["ruby","redis","performance","optimization"]',
  'created_at' => Familia.now.to_i.to_s,
  'score' => '98.7',
  'simple_string' => 'Just a plain string value',
  'nested_data' => '{"user":{"profile":{"settings":{"theme":"dark","notifications":true}}}}',
  'empty_string' => '',
  'nil_value' => nil,
}

# Persist sample data to Redis
user = CorrectnessTestUser.new(**sample_data)
user.save

# Get the raw hash data directly from Redis
raw_hash = CorrectnessTestUser.dbclient.hgetall(user.dbkey)

puts 'Correctness Test: Deserialization Strategies'
puts '=' * 70
puts "\nTesting with #{raw_hash.keys.size} fields"
puts "\n"

# Strategy 1: Current field-by-field (reference implementation)
def strategy_current(fields, klass)
  deserialized = fields.transform_values { |value| klass.new.deserialize_value(value) }
  klass.new(**deserialized)
end

# Strategy 2: Bulk JSON round-trip
def strategy_bulk_json(fields, klass)
  parsed = JSON.parse(JSON.dump(fields))
  klass.new(**parsed)
end

# Strategy 3: Selective deserialization (only JSON-looking strings)
def strategy_selective(fields, klass)
  deserialized = fields.transform_values do |value|
    if value.to_s.start_with?('{', '[')
      begin
        JSON.parse(value, symbolize_names: true)
      rescue JSON::ParserError
        value
      end
    else
      value
    end
  end
  klass.new(**deserialized)
end

# Create objects using each strategy
current_obj = strategy_current(raw_hash, CorrectnessTestUser)
bulk_obj = strategy_bulk_json(raw_hash, CorrectnessTestUser)
selective_obj = strategy_selective(raw_hash, CorrectnessTestUser)

# Test helper to compare field values
def compare_values(field, current_val, test_val, strategy_name)
  current_class = current_val.class
  test_class = test_val.class

  if current_val == test_val && current_class == test_class
    { status: :pass, field: field, strategy: strategy_name }
  else
    {
      status: :fail,
      field: field,
      strategy: strategy_name,
      current: { value: current_val.inspect, class: current_class },
      test: { value: test_val.inspect, class: test_class },
    }
  end
end

# Run correctness tests
results = []
fields_to_test = CorrectnessTestUser.fields

puts "Testing #{fields_to_test.size} fields across strategies...\n\n"

# Test Bulk JSON strategy
puts 'Strategy: Bulk JSON round-trip'
puts '-' * 70
fields_to_test.each do |field|
  current_val = current_obj.send(field)
  test_val = bulk_obj.send(field)
  result = compare_values(field, current_val, test_val, 'Bulk JSON')
  results << result

  if result[:status] == :pass
    puts "  ✓ #{field}: #{test_val.inspect} (#{test_val.class})"
  else
    puts "  ✗ #{field}: MISMATCH"
    puts "    Current: #{result[:current][:value]} (#{result[:current][:class]})"
    puts "    Bulk:    #{result[:test][:value]} (#{result[:test][:class]})"
  end
end

puts "\n"

# Test Selective strategy
puts 'Strategy: Selective (only JSON-like strings)'
puts '-' * 70
fields_to_test.each do |field|
  current_val = current_obj.send(field)
  test_val = selective_obj.send(field)
  result = compare_values(field, current_val, test_val, 'Selective')
  results << result

  if result[:status] == :pass
    puts "  ✓ #{field}: #{test_val.inspect} (#{test_val.class})"
  else
    puts "  ✗ #{field}: MISMATCH"
    puts "    Current:   #{result[:current][:value]} (#{result[:current][:class]})"
    puts "    Selective: #{result[:test][:value]} (#{result[:test][:class]})"
  end
end

puts "\n" + ('=' * 70)
puts 'SUMMARY'
puts '=' * 70

# Group results by strategy
by_strategy = results.group_by { |r| r[:strategy] }

by_strategy.each do |strategy, strategy_results|
  passed = strategy_results.count { |r| r[:status] == :pass }
  failed = strategy_results.count { |r| r[:status] == :fail }
  total = strategy_results.size

  status_icon = failed == 0 ? '✓' : '✗'
  puts "\n#{status_icon} #{strategy}: #{passed}/#{total} passed"

  next unless failed > 0

  puts '  Failed fields:'
  strategy_results.select { |r| r[:status] == :fail }.each do |result|
    puts "    - #{result[:field]}"
  end
end

# Overall assessment
all_passed = results.all? { |r| r[:status] == :pass }

puts "\n" + ('=' * 70)
puts 'VERDICT'
puts '=' * 70

if all_passed
  puts '✓ All strategies produce identical results to current implementation'
  puts '  Safe to use for optimization'
else
  puts '✗ Some strategies produce different results'
  puts '  Review failures before implementing'
end

puts "\n" + ('=' * 70)
puts 'RECOMMENDATIONS'
puts '=' * 70

# Analyze which strategies passed
bulk_passed = by_strategy['Bulk JSON'].all? { |r| r[:status] == :pass }
selective_passed = by_strategy['Selective'].all? { |r| r[:status] == :pass }

if bulk_passed && selective_passed
  puts '✓ Both Bulk JSON and Selective strategies are correct'
  puts '  → Use Selective for best performance (+15-18% overhead)'
  puts '  → Use Bulk JSON for simplicity (+20% overhead)'
elsif bulk_passed
  puts '✓ Bulk JSON strategy is correct'
  puts '  → Safe to implement (+20% overhead vs baseline)'
elsif selective_passed
  puts '✓ Selective strategy is correct'
  puts '  → Safe to implement (+15-18% overhead vs baseline)'
else
  puts '✗ No alternative strategies passed all tests'
  puts '  → Stick with current implementation'
  puts '  → Or fix identified issues in failing strategies'
end

# Cleanup
user.destroy!

__END__

# Expected output:
#
# All strategies should pass if they correctly handle:
# - Simple strings (no parsing needed)
# - JSON objects (hashes)
# - JSON arrays
# - Numbers as strings
# - Empty strings
# - Nil values
# - Nested JSON structures
