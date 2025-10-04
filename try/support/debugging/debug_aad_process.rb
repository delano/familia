#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative '../helpers/test_helpers'

puts "Debugging AAD during encrypt/decrypt process..."

# Setup encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class DebugModelA < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

class DebugModelB < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

# Patch the EncryptedFieldType to add debug output
class Familia::EncryptedFieldType
  alias_method :original_encrypt_value, :encrypt_value
  alias_method :original_decrypt_value, :decrypt_value
  alias_method :original_build_aad, :build_aad

  def encrypt_value(record, value)
    context = build_context(record)
    aad = build_aad(record)
    puts "[ENCRYPT] Class: #{record.class}, ID: #{record.identifier}, Context: #{context}, AAD: #{aad}"
    original_encrypt_value(record, value)
  end

  def decrypt_value(record, encrypted)
    context = build_context(record)
    aad = build_aad(record)
    puts "[DECRYPT] Class: #{record.class}, ID: #{record.identifier}, Context: #{context}, AAD: #{aad}"
    original_decrypt_value(record, encrypted)
  end

  def build_aad(record)
    aad = original_build_aad(record)
    puts "[BUILD_AAD] Class: #{record.class}, ID: #{record.identifier}, AAD: #{aad}"
    aad
  end
end

# Clean database
Familia.dbclient.flushdb

model_a = DebugModelA.new(id: 'same-id')
model_b = DebugModelB.new(id: 'same-id')

puts "\n=== ENCRYPTION PHASE ==="
puts "Encrypting for ModelA:"
model_a.api_key = 'secret-key'
cipher_a = model_a.instance_variable_get(:@api_key)

puts "\nEncrypting for ModelB:"
model_b.api_key = 'secret-key'
cipher_b = model_b.instance_variable_get(:@api_key)

puts "\n=== DECRYPTION PHASE - Same Context ==="
puts "Decrypting ModelA with ModelA context:"
model_a.api_key.reveal { |plain| puts "Result: #{plain}" }

puts "\n=== DECRYPTION PHASE - Cross Context ==="
puts "Setting ModelB cipher into ModelA and trying to decrypt:"
model_a.instance_variable_set(:@api_key, cipher_b)
begin
  model_a.api_key.reveal { |plain| puts "ERROR: Cross-context worked: #{plain}" }
rescue => e
  puts "SUCCESS: Cross-context failed as expected: #{e.class}: #{e.message}"
end
