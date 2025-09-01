#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Debugging secure_by_default_behavior test failure..."

# Setup encryption keys for testing
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class DebugSecureUserAccount < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :username
  field :email
  encrypted_field :password_hash
  encrypted_field :api_secret
  encrypted_field :recovery_key
end

# Patch for debugging
class Familia::EncryptedFieldType
  alias_method :original_encrypt_value, :encrypt_value
  alias_method :original_decrypt_value, :decrypt_value

  def encrypt_value(record, value)
    aad = build_aad(record)
    puts "[ENCRYPT] #{record.class}##{@name}: exists=#{record.exists?}, AAD=#{aad}"
    original_encrypt_value(record, value)
  end

  def decrypt_value(record, encrypted)
    aad = build_aad(record)
    puts "[DECRYPT] #{record.class}##{@name}: exists=#{record.exists?}, AAD=#{aad}"
    original_decrypt_value(record, encrypted)
  end
end

# Clean database
Familia.dbclient.flushdb

puts "\n=== CREATION AND ENCRYPTION ==="
user = DebugSecureUserAccount.new(id: "user123")
puts "After new: exists=#{user.exists?}"

user.username = "john_doe"
user.email = "john@example.com"
user.password_hash = "bcrypt$2a$12$abcdef..."
user.api_secret = "secret-api-key-12345"

puts "\n=== SAVE TO DATABASE ==="
result = user.save
puts "Save result: #{result}"
puts "After save: exists=#{user.exists?}"

puts "\n=== FRESH LOAD FROM DATABASE ==="
fresh_user = DebugSecureUserAccount.load("user123")
puts "Fresh user loaded: exists=#{fresh_user.exists?}"

puts "\n=== DECRYPTION ATTEMPT ==="
begin
  fresh_user.password_hash.reveal do |plaintext|
    puts "SUCCESS: Decrypted password_hash: #{plaintext}"
  end
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
  puts "This suggests AAD mismatch between save and load"
end
