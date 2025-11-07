# try/support/debugging/debug_provider.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing provider-level decryption..."

# Setup
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Simulate the conditions during encryption vs decryption
class TestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

# Clean database
Familia.dbclient.flushdb

puts "\n=== DIRECT ENCRYPTION/DECRYPTION TEST ==="

# Test direct encryption/decryption with different AAD values
plaintext = "test-secret"
context = "TestModel:secret:test1"

# Scenario 1: Encrypt with AAD = nil (before save)
puts "Encrypting with AAD = nil..."
encrypted_json_1 = Familia::Encryption.encrypt(plaintext, context: context, additional_data: nil)
puts "Encrypted: #{encrypted_json_1}"

# Try to decrypt with AAD = nil
puts "Decrypting with AAD = nil..."
decrypted_1 = Familia::Encryption.decrypt(encrypted_json_1, context: context, additional_data: nil)
puts "Decrypted: #{decrypted_1}"

# Try to decrypt with AAD = "test1" (what happens after load)
puts "Decrypting with AAD = 'test1'..."
begin
  decrypted_2 = Familia::Encryption.decrypt(encrypted_json_1, context: context, additional_data: "test1")
  puts "Decrypted: #{decrypted_2}"
rescue => e
  puts "Decryption failed: #{e.class}: #{e.message}"
end

# Scenario 2: Encrypt with AAD = "test1" (after save)
puts "\nEncrypting with AAD = 'test1'..."
encrypted_json_2 = Familia::Encryption.encrypt(plaintext, context: context, additional_data: "test1")
puts "Encrypted: #{encrypted_json_2}"

# Try to decrypt with AAD = "test1"
puts "Decrypting with AAD = 'test1'..."
decrypted_3 = Familia::Encryption.decrypt(encrypted_json_2, context: context, additional_data: "test1")
puts "Decrypted: #{decrypted_3}"

# Try to decrypt with AAD = nil
puts "Decrypting with AAD = nil..."
begin
  decrypted_4 = Familia::Encryption.decrypt(encrypted_json_2, context: context, additional_data: nil)
  puts "Decrypted: #{decrypted_4}"
rescue => e
  puts "Decryption failed: #{e.class}: #{e.message}"
end
