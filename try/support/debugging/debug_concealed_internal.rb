#!/usr/bin/env ruby
# try/support/debugging/debug_concealed_internal.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative '../helpers/test_helpers'

puts "Testing ConcealedString internal call chain..."

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

puts "\n=== CONCEALED STRING INTERNAL DEBUGGING ==="

# Create and save model
model = TestModel.new(id: 'test1')
model.secret = 'plaintext-secret'
model.save

# Load model from database
loaded_model = TestModel.load('test1')
concealed_string = loaded_model.secret

# Access internal ConcealedString components
puts "ConcealedString @encrypted_data: #{concealed_string.instance_variable_get(:@encrypted_data)}"
puts "ConcealedString @record: #{concealed_string.instance_variable_get(:@record)}"
puts "ConcealedString @field_type: #{concealed_string.instance_variable_get(:@field_type)}"

record = concealed_string.instance_variable_get(:@record)
field_type = concealed_string.instance_variable_get(:@field_type)
encrypted_data = concealed_string.instance_variable_get(:@encrypted_data)

puts "\n=== STEP BY STEP DECRYPTION ==="
puts "Record class: #{record.class}"
puts "Record identifier: #{record.identifier}"
puts "Record exists?: #{record.exists?}"
puts "Field type class: #{field_type.class}"

# Test the exact same call that ConcealedString.reveal makes
puts "\nCalling field_type.decrypt_value(record, encrypted_data)..."
begin
  result = field_type.decrypt_value(record, encrypted_data)
  puts "decrypt_value result: #{result}"
  puts "Result class: #{result.class}"
rescue => e
  puts "decrypt_value ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(10)
end
