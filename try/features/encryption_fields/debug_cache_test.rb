#!/usr/bin/env ruby

# Debug script to trace encryption cache behavior

require 'base64'
require 'bundler/setup'

require_relative '../../helpers/test_helpers'

# Setup test configuration
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clear any existing cache
Thread.current[:familia_key_cache] = nil
puts "1. Initial cache state: #{Thread.current[:familia_key_cache].inspect}"

# Define test model
class CacheTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  encrypted_field :field_a
  encrypted_field :field_b
end

puts "\n2. Creating model instance..."
user = CacheTestModel.new(user_id: 'user1')
puts "   Cache after model creation: #{Thread.current[:familia_key_cache].inspect}"

puts "\n3. Setting field_a..."
user.field_a = 'test-value-a'
puts "   Cache after field_a setter: #{Thread.current[:familia_key_cache].inspect}"

puts "\n4. Setting field_b..."
user.field_b = 'test-value-b'
puts "   Cache after field_b setter: #{Thread.current[:familia_key_cache].inspect}"

puts "\n5. Getting field_a..."
value_a = user.field_a
puts "   Retrieved value: #{value_a}"
puts "   Cache after field_a getter: #{Thread.current[:familia_key_cache].inspect}"

puts "\n6. Getting field_b..."
value_b = user.field_b
puts "   Retrieved value: #{value_b}"
puts "   Cache after field_b getter: #{Thread.current[:familia_key_cache].inspect}"

puts "\n7. Final cache analysis:"
cache = Thread.current[:familia_key_cache]
if cache
  puts "   Cache size: #{cache.size}"
  puts "   Cache keys: #{cache.keys.inspect}"
  cache.each do |key, value|
    puts "   #{key} => [#{value.bytesize} bytes]"
  end
else
  puts "   Cache is nil"
end
