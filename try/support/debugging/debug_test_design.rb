#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Understanding the test design and expected behavior..."

# Setup encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class TestModelA < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

class TestModelB < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

# Clean database
Familia.dbclient.flushdb

model_a = TestModelA.new(id: 'same-id')
model_b = TestModelB.new(id: 'same-id')

model_a.api_key = 'secret-key'
model_b.api_key = 'secret-key'

cipher_a = model_a.instance_variable_get(:@api_key)
cipher_b = model_b.instance_variable_get(:@api_key)

puts "cipher_a class: #{cipher_a.class}"
puts "cipher_b class: #{cipher_b.class}"

# What the current tests do:
puts "\n=== Current test approach ==="
model_a.instance_variable_set(:@api_key, cipher_b)
result = model_a.api_key
puts "After setting cipher_b into model_a:"
puts "  api_key returns: #{result.class}"
puts "  This should be ConcealedString and succeed"

# What would test ACTUAL cross-context isolation:
puts "\n=== Testing actual cross-context isolation ==="
puts "The REAL test should be trying to decrypt:"
begin
  result.reveal do |plain|
    puts "  Cross-context decryption succeeded: #{plain} (BAD)"
  end
rescue => e
  puts "  Cross-context decryption failed: #{e.class} (GOOD)"
end

# Try with raw encrypted JSON to see if that behaves differently:
puts "\n=== Testing with raw encrypted JSON ==="
raw_encrypted_b = cipher_b.encrypted_value
puts "Raw encrypted from B: #{raw_encrypted_b}"

# Try to set raw encrypted JSON and see what happens
model_a.api_key = raw_encrypted_b  # This should wrap it in ConcealedString
result2 = model_a.api_key
puts "After setting raw encrypted JSON:"
puts "  api_key returns: #{result2.class}"

begin
  result2.reveal do |plain|
    puts "  Raw JSON decryption result: #{plain}"
  end
rescue => e
  puts "  Raw JSON decryption failed: #{e.class}: #{e.message}"
end
