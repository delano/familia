#!/usr/bin/env ruby
# try/support/debugging/debug_fresh_cross_context.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing cross-context validation with fresh encryption after AAD fix..."

# Setup encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class FreshModelA < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

class FreshModelB < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

# Clean database
Familia.dbclient.flushdb

model_a = FreshModelA.new(id: 'same-id')
model_b = FreshModelB.new(id: 'same-id')

puts "=== Fresh Encryption Test ==="
model_a.api_key = 'secret-key'
model_b.api_key = 'secret-key'

cipher_a = model_a.instance_variable_get(:@api_key)
cipher_b = model_b.instance_variable_get(:@api_key)

puts "cipher_a encrypted: #{cipher_a.encrypted_value}"
puts "cipher_b encrypted: #{cipher_b.encrypted_value}"

# Now try cross-context access
puts "\n=== Cross-context test ==="
model_a.instance_variable_set(:@api_key, cipher_b)
puts "UnsortedSet cipher_b into model_a"

begin
  result = model_a.api_key
  puts "Got result: #{result.class}"

  # Try to reveal it - this should fail now
  result.reveal do |plaintext|
    puts "ERROR: Successfully revealed: #{plaintext} - should have failed!"
  end
rescue Familia::EncryptionError => e
  puts "SUCCESS: Got expected encryption error: #{e.message}"
rescue => e
  puts "Got unexpected error: #{e.class}: #{e.message}"
end

puts "\n=== Same-context test (should work) ==="
begin
  model_a.instance_variable_set(:@api_key, cipher_a) # Back to original
  result = model_a.api_key
  result.reveal do |plaintext|
    puts "SUCCESS: Same-context decryption worked: #{plaintext}"
  end
rescue => e
  puts "ERROR: Same-context failed: #{e.class}: #{e.message}"
end
