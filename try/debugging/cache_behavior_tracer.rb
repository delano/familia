#!/usr/bin/env ruby
# Debug script to trace encryption cache behavior and key derivation

require 'base64'
require 'bundler/setup'
require_relative '../helpers/test_helpers'

puts "=== Encryption Cache Behavior Tracer ==="
puts

# Setup test configuration
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clear any existing cache
Thread.current[:familia_key_cache] = nil
puts "1. Initial Cache State:"
puts "   Cache: #{Thread.current[:familia_key_cache].inspect}"
puts

# Define test model with multiple encrypted fields
class CacheTraceModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  encrypted_field :field_a
  encrypted_field :field_b
  encrypted_field :field_c
end

puts "2. Model Creation:"
user = CacheTraceModel.new(user_id: 'cache-user-1')
puts "   After model creation: #{Thread.current[:familia_key_cache].inspect}"
puts

puts "3. Setting Encrypted Fields:"
['field_a', 'field_b', 'field_c'].each_with_index do |field, i|
  puts "   Setting #{field}..."
  user.public_send("#{field}=", "test-value-#{i+1}")
  cache = Thread.current[:familia_key_cache]
  if cache
    puts "     Cache size: #{cache.size}"
    puts "     Cache keys: #{cache.keys.inspect}"
  else
    puts "     Cache: nil"
  end
end
puts

puts "4. Reading Encrypted Fields:"
['field_a', 'field_b', 'field_c'].each do |field|
  puts "   Reading #{field}..."
  value = user.public_send(field)
  puts "     Retrieved: #{value}"
  cache = Thread.current[:familia_key_cache]
  if cache
    puts "     Cache size: #{cache.size}"
    puts "     Cache keys: #{cache.keys.inspect}"
  else
    puts "     Cache: nil"
  end
end
puts

puts "5. Final Cache Analysis:"
cache = Thread.current[:familia_key_cache]
if cache && !cache.empty?
  puts "   Cache size: #{cache.size} entries"
  cache.each_with_index do |(key, value), i|
    puts "   Entry #{i+1}: #{key} => [#{value.bytesize} bytes]"
  end
else
  puts "   Cache is empty or nil"
end
puts

# Test cache behavior with multiple models
puts "6. Multiple Models Cache Test:"
user2 = CacheTraceModel.new(user_id: 'cache-user-2')
user2.field_a = 'different-value'
puts "   After second model field set:"
cache = Thread.current[:familia_key_cache]
if cache
  puts "     Cache size: #{cache.size}"
  puts "     Unique contexts: #{cache.keys.map { |k| k.split(':').last }.uniq.size}"
end

puts
puts "=== Cache Tracing Complete ==="
