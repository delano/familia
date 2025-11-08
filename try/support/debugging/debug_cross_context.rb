#!/usr/bin/env ruby
# try/support/debugging/debug_cross_context.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Debugging cross-context validation..."

# Setup encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class ModelA < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

class ModelB < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

# Clean database
Familia.dbclient.flushdb

model_a = ModelA.new(id: 'same-id')
model_b = ModelB.new(id: 'same-id')

model_a.api_key = 'secret-key'
model_b.api_key = 'secret-key'

cipher_a = model_a.instance_variable_get(:@api_key)
cipher_b = model_b.instance_variable_get(:@api_key)

puts "cipher_a: #{cipher_a.class} - #{cipher_a.encrypted_value}"
puts "cipher_b: #{cipher_b.class} - #{cipher_b.encrypted_value}"

# Now try cross-context access
puts "\n=== Cross-context test ==="
model_a.instance_variable_set(:@api_key, cipher_b)
puts "UnsortedSet cipher_b into model_a"

begin
  result = model_a.api_key
  puts "Got result: #{result.class} - should be ConcealedString"

  # Try to reveal it
  result.reveal do |plaintext|
    puts "Successfully revealed: #{plaintext}"
  end
  puts "ERROR: Cross-context decryption should have failed!"
rescue Familia::EncryptionError => e
  puts "SUCCESS: Got expected encryption error: #{e.message}"
rescue => e
  puts "Got unexpected error: #{e.class}: #{e.message}"
end
