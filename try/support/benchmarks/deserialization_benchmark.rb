#!/usr/bin/env ruby

# Benchmark: Field deserialization strategies in find_by_dbkey
#
# Compares different approaches to deserializing Redis hash values
# when loading Horreum objects from the database.
#
# Usage:
#
#   $ ruby try/support/benchmarks/deserialization_benchmark.rb
#   ======================================================================
#   RESULTS SUMMARY (baseline: direct assignment)
#   ======================================================================
#
#   Baseline (no deserialization): 0.151312s
#
#   Deserialization strategies:
#   1. Selective (only JSON-like strings): 0.174016s (1.15x baseline, +15.0% overhead) 🏆 FASTEST
#   2. Bulk JSON round-trip (parse/dump): 0.183926s (1.22x baseline, +21.6% overhead)
#   3. Cached instance + transform: 0.320223s (2.12x baseline, +111.6% overhead)
#   4. Current (field-by-field transform_values): 0.49568s (3.28x baseline, +227.6% overhead)

require_relative '../../../lib/familia'
require 'benchmark'
require 'json'

# Setup Redis connection
Familia.uri = ENV['REDIS_URI'] || 'redis://localhost:2525/3'

# Sample model with various field types
class BenchmarkUser < Familia::Horreum
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
end

# Create sample data with realistic values
sample_data = {
  'user_id' => 'user_12345',
  'name' => 'John Doe',
  'email' => 'john.doe@example.com',
  'age' => '35',
  'active' => 'true',
  'metadata' => '{"role":"admin","department":"engineering","level":5}',
  'tags' => '["ruby","redis","performance","optimization"]',
  'created_at' => Time.now.to_i.to_s,
  'score' => '98.7',
  'simple_string' => 'Just a plain string value',
}

# Persist sample data to Redis
user = BenchmarkUser.new(**sample_data)
user.save

# Get the raw hash data directly from Redis (what find_by_dbkey gets)
raw_hash = BenchmarkUser.dbclient.hgetall(user.dbkey)

puts 'Benchmarking deserialization strategies'
puts "Sample data fields: #{raw_hash.keys.size}"
puts "Raw hash: #{raw_hash.inspect}"
puts "\n"

# Strategy 1: Current field-by-field with transform_values
def strategy_current(fields, klass)
  deserialized = fields.transform_values { |value| klass.new.deserialize_value(value) }
  klass.new(**deserialized)
end

# Strategy 2: Bulk JSON round-trip
def strategy_bulk_json(fields, klass)
  parsed = JSON.parse(JSON.dump(fields))
  klass.new(**parsed)
end

# Strategy 3: Direct assignment without deserialization
def strategy_direct(fields, klass)
  klass.new(**fields)
end

# Strategy 4: Selective deserialization (only JSON-looking strings)
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

# Strategy 5: Cached instance + transform
def strategy_cached_instance(fields, klass)
  instance = klass.new
  deserialized = fields.transform_values { |value| instance.deserialize_value(value) }
  klass.new(**deserialized)
end

iterations = 10_000

puts "Running #{iterations} iterations per strategy...\n\n"

strategies = {
  'Current (field-by-field transform_values)' => :strategy_current,
  'Bulk JSON round-trip (parse/dump)' => :strategy_bulk_json,
  'Direct (no deserialization)' => :strategy_direct,
  'Selective (only parse JSON-like strings)' => :strategy_selective,
  'Cached instance + transform' => :strategy_cached_instance,
}

results = {}

strategies.each do |name, method_name|
  time = Benchmark.measure do
    iterations.times do
      send(method_name, raw_hash, BenchmarkUser)
    end
  end
  results[name] = time.real
  puts "#{name}: #{time.real.round(6)} seconds (#{(iterations / time.real).round(0)} ops/sec)"
end

puts "\n" + ('=' * 70)
puts 'RESULTS SUMMARY (baseline: direct assignment)'
puts '=' * 70

# Use direct assignment as baseline (obviously fastest but incorrect)
baseline = results['Direct (no deserialization)']

# Sort deserialization strategies only (exclude baseline)
deserialization_strategies = results.reject { |name, _| name == 'Direct (no deserialization)' }
sorted = deserialization_strategies.sort_by { |_, time| time }

puts "
Baseline (no deserialization): #{baseline.round(6)}s"
puts "
Deserialization strategies:
"

sorted.each_with_index do |(name, time), index|
  overhead = ((time / baseline - 1) * 100).round(1)
  vs_baseline = (time / baseline).round(2)
  marker = index == 0 ? '🏆 FASTEST' : ''
  puts "#{index + 1}. #{name}: #{time.round(6)}s (#{vs_baseline}x baseline, +#{overhead}% overhead) #{marker}"
end

puts "
" + ('=' * 70)
puts 'RECOMMENDATIONS'
puts '=' * 70

puts 'Best strategy depends on your data:'
puts '  • Mostly simple strings → Direct or Selective'
puts '  • Mixed types with JSON → Current (field-by-field)'
puts '  • Heavy JSON payloads → Consider lazy deserialization'

# Cleanup
user.destroy!

__END__

# Example output expectations:
#
# Current approach should be moderately fast
# Bulk JSON round-trip should be slower (extra serialization step)
# Direct assignment should be fastest but incorrect for complex types
# Selective should be fast for simple data, slower for JSON-heavy data
