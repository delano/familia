#!/usr/bin/env ruby
# try/support/debugging/debug_field_decrypt.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing field-level decryption path..."

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

puts "\n=== FIELD-LEVEL DECRYPTION PATH ==="

# Create and save model
model = TestModel.new(id: 'test1')
model.secret = 'plaintext-secret'
model.save

# Load model from database
loaded_model = TestModel.load('test1')

# Get the field type and test direct decryption
puts "Available field types: #{TestModel.field_types.inspect}"
secret_field_type = TestModel.field_types[:secret]
puts "Field type class: #{secret_field_type.class}"

# Get the raw encrypted data
raw_encrypted = Familia.dbclient.hget('testmodel:test1:object', 'secret')
puts "Raw encrypted from DB: #{raw_encrypted}"

puts "\n=== DIRECT FIELD TYPE DECRYPTION ==="

# Test the field type decrypt_value method directly
puts "Testing field_type.decrypt_value with loaded model..."
begin
  direct_decrypted = secret_field_type.decrypt_value(loaded_model, raw_encrypted)
  puts "Direct field decrypt result: #{direct_decrypted}"
  puts "Result class: #{direct_decrypted.class}"
rescue => e
  puts "Direct field decrypt ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n=== AAD INVESTIGATION ==="
puts "loaded_model.exists?: #{loaded_model.exists?}"
puts "loaded_model.identifier: #{loaded_model.identifier}"

# Build the same context and AAD that the field type would use
context = "TestModel:secret:#{loaded_model.identifier}"
puts "Context: #{context}"

# Build AAD using the same logic as EncryptedFieldType#build_aad
aad = loaded_model.exists? ? loaded_model.identifier : nil
puts "AAD: #{aad.inspect}"

puts "\n=== MANUAL FAMILIA::ENCRYPTION CALL ==="
begin
  manual_decrypted = Familia::Encryption.decrypt(raw_encrypted, context: context, additional_data: aad)
  puts "Manual decrypt result: #{manual_decrypted}"
rescue => e
  puts "Manual decrypt ERROR: #{e.class}: #{e.message}"
end
