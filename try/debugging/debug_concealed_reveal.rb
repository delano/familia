#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing ConcealedString.reveal error handling..."

class TestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clean database
Familia.dbclient.flushdb

puts "\n=== CONCEALED STRING REVEAL ERROR PATH ==="

# Create and save model (encrypt with AAD = nil)
model = TestModel.new(id: 'test1')
model.secret = 'plaintext-secret'
model.save

# Load model from database (decrypt with AAD = "test1")
loaded_model = TestModel.load('test1')

puts "Loaded model secret class: #{loaded_model.secret.class}"

# Test ConcealedString.reveal directly
concealed_string = loaded_model.secret
puts "ConcealedString object: #{concealed_string.inspect}"

puts "\nTesting ConcealedString.reveal..."
begin
  result = concealed_string.reveal do |plaintext|
    puts "Inside reveal block, plaintext: #{plaintext}"
    plaintext  # Return the plaintext
  end
  puts "Reveal result: #{result}"
  puts "Result class: #{result.class}"
rescue => e
  puts "Reveal ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\nTesting ConcealedString.reveal_for_testing..."
begin
  result = concealed_string.reveal_for_testing
  puts "reveal_for_testing result: #{result}"
  puts "Result class: #{result.class}"
rescue => e
  puts "reveal_for_testing ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end
