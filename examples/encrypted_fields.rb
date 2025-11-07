# examples/encrypted_fields.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby

# examples/encrypted_fields.rb
#
# Demonstrates the EncryptedFields feature for protecting sensitive data.
# This feature provides transparent encryption/decryption of sensitive fields
# using strong cryptographic algorithms with field-specific key derivation.

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'familia'

# Configure connection
Familia.uri = 'redis://localhost:2525/3'

puts '=== Encrypted Fields Feature Examples ==='
puts

# Configure encryption keys for examples
Familia.configure do |config|
  config.encryption_keys = {
    v1: 'dGVzdGtleWZvcmV4YW1wbGVzMTIzNDU2Nzg5MA==', # Base64 encoded 32 bytes
    v2: 'bmV3ZXJrZXlmb3JleGFtcGxlczEyMzQ1Njc4OTA=', # Base64 encoded 32 bytes
  }
  config.current_key_version = :v2
  config.encryption_personalization = 'FamiliaExamples'
end

# Validate configuration before proceeding
begin
  Familia::Encryption.validate_configuration!
  puts '✓ Encryption configuration validated'
  puts "  Algorithm: #{Familia::Encryption.status[:default_algorithm]}"
  puts "  Available algorithms: #{Familia::Encryption.status[:available_algorithms].join(', ')}"
  puts "  Key versions: #{Familia::Encryption.status[:key_versions].join(', ')}"
  puts
rescue Familia::EncryptionError => e
  puts "✗ Encryption configuration error: #{e.message}"
  exit 1
end

# Example 1: Basic encrypted fields
class SecureUser < Familia::Horreum
  feature :encrypted_fields

  identifier_field :email
  field :email                    # stored as plaintext in the database
  field :name
  encrypted_field :ssn            # store as an encrypted string in the database
  encrypted_field :credit_card
  encrypted_field :notes
  field :created_at
end

puts 'Example 1: Basic encrypted fields'
user = SecureUser.new(
  email: 'alice@example.com',
  name: 'Alice Windows',
  ssn: '123-45-6789',
  credit_card: '4111-1111-1111-1111',
  notes: 'VIP customer with special handling',
  created_at: Familia.now.to_i
)

user.save
puts '✓ User saved with encrypted fields'

# Demonstrate transparent access
puts "Name (plaintext): #{user.name}"
puts "SSN (encrypted): #{user.ssn.class} -> #{user.ssn.reveal}"
puts "Credit card: #{user.credit_card.reveal}"
puts "Notes: #{user.notes.reveal}"

# Show how ConcealedString protects data in logs
puts "SSN to_s (safe for logging): #{user.ssn}"
puts "SSN inspect (safe for logging): #{user.ssn.inspect}"
puts

# Example 2: Encrypted fields with Additional Authenticated Data (AAD)
class SecureDocument < Familia::Horreum
  feature :encrypted_fields

  identifier_field :doc_id
  field :doc_id
  field :title                    # Plaintext
  field :owner_id                 # Plaintext
  field :classification # Plaintext
  encrypted_field :content, aad_fields: %i[doc_id owner_id classification]
  encrypted_field :summary        # No AAD
  field :created_at               # Plaintext
end

puts 'Example 2: Encrypted fields with Additional Authenticated Data'
doc = SecureDocument.new(
  doc_id: 'DOC-2024-001',
  title: 'Strategic Plan',
  owner_id: 'user123',
  classification: 'confidential',
  content: 'This document contains sensitive strategic information...',
  summary: 'Strategic planning document for Q1 2024',
  created_at: Familia.now.to_i
)

doc.save
puts '✓ Document saved with AAD-protected content'

# AAD ensures content can only be decrypted with matching metadata
puts "Title: #{doc.title}"
puts "Content (with AAD protection): #{doc.content.reveal}"
puts "Summary (no AAD): #{doc.summary.reveal}"
puts

# Example 3: Performance optimization with request caching
class VaultEntry < Familia::Horreum
  feature :encrypted_fields

  identifier_field :entry_id
  field :entry_id
  encrypted_field :api_key
  encrypted_field :secret_token
  encrypted_field :private_key
  encrypted_field :webhook_url
end

puts 'Example 3: Performance optimization with request caching'
entries = []

# Without caching - each field derives keys independently
start_time = Time.now
5.times do |i|
  private_key_pem = <<~PEM
    -----BEGIN PRIVATE KEY-----
    FAKE_EXAMPLE_KEY_FOR_TESTING_ONLY
    FAKE_EXAMPLE_KEY_FOR_TESTING_ONLY
    -----END PRIVATE KEY-----
  PEM

  entry = VaultEntry.new(
    entry_id: "entry_#{i}",
    api_key: "sk_test_key_#{i}",
    secret_token: "token_#{i}_secret",
    private_key: private_key_pem.strip,
    webhook_url: "https://api.example.com/webhook/#{i}"
  )
  entry.save
  entries << entry
end
no_cache_time = Time.now - start_time

# With caching - reuses derived keys within the block
start_time = Time.now
Familia::Encryption.with_request_cache do
  5.times do |i|
    private_key_pem = <<~PEM
      -----BEGIN PRIVATE KEY-----
      FAKE_EXAMPLE_KEY_FOR_TESTING_ONLY
      FAKE_EXAMPLE_KEY_FOR_TESTING_ONLY
      -----END PRIVATE KEY-----
    PEM

    entry = VaultEntry.new(
      entry_id: "cached_entry_#{i}",
      api_key: "sk_test_key_cached_#{i}",
      secret_token: "token_cached_#{i}_secret",
      private_key: private_key_pem.strip,
      webhook_url: "https://api.example.com/webhook/cached/#{i}"
    )
    entry.save
    entries << entry
  end
end
cached_time = Time.now - start_time

puts "Encryption without caching: #{(no_cache_time * 1000).round(2)}ms"
puts "Encryption with caching: #{(cached_time * 1000).round(2)}ms"
puts "Performance improvement: #{((no_cache_time - cached_time) / no_cache_time * 100).round(1)}%"
puts

# Example 4: Key rotation simulation
class RotationTest < Familia::Horreum
  feature :encrypted_fields

  identifier_field :test_id
  field :test_id
  encrypted_field :sensitive_data
end

puts 'Example 4: Key rotation demonstration'
rotation_obj = RotationTest.new(
  test_id: 'rotation_test',
  sensitive_data: 'Original sensitive data encrypted with v2 key'
)
rotation_obj.save

puts "Original data encrypted with key version: #{Familia.config.current_key_version}"
puts "Data: #{rotation_obj.sensitive_data.reveal}"

# Check encryption status before rotation
status_before = rotation_obj.encrypted_fields_status
puts "Encryption status before rotation: #{status_before}"

# Simulate key rotation - switch to v1 for demonstration
Familia.config.current_key_version = :v1

# Re-encrypt with new current key
rotation_obj.sensitive_data = 'Updated data encrypted with v1 key'
rotation_obj.re_encrypt_fields!
rotation_obj.save

puts "After rotation to key version: #{Familia.config.current_key_version}"
puts "Data: #{rotation_obj.sensitive_data.reveal}"

# Check encryption status after rotation
status_after = rotation_obj.encrypted_fields_status
puts "Encryption status after rotation: #{status_after}"

# Switch back to v2
Familia.config.current_key_version = :v2
puts

# Example 5: Memory safety and cleanup
class MemoryTest < Familia::Horreum
  feature :encrypted_fields

  identifier_field :mem_id
  field :mem_id
  encrypted_field :secret_one
  encrypted_field :secret_two
  encrypted_field :secret_three
end

puts 'Example 5: Memory safety and cleanup'
mem_obj = MemoryTest.new(
  mem_id: 'memory_test',
  secret_one: 'First secret value',
  secret_two: 'Second secret value',
  secret_three: 'Third secret value'
)

puts "Has encrypted data: #{mem_obj.encrypted_data?}"
puts "Fields cleared: #{mem_obj.encrypted_fields_cleared?}"

# Access some fields to load them into memory
puts "Secret one: #{mem_obj.secret_one.reveal}"
puts "Secret two: #{mem_obj.secret_two.reveal}"

# Clear specific field
mem_obj.secret_one.clear!
puts "Secret one cleared: #{mem_obj.secret_one.cleared?}"

# Clear all encrypted fields
mem_obj.clear_encrypted_fields!
puts "All fields cleared: #{mem_obj.encrypted_fields_cleared?}"
puts

# Example 6: Error handling and validation
puts 'Example 6: Error handling and validation'

# Test with invalid configuration
begin
  old_keys = Familia.config.encryption_keys
  Familia.config.encryption_keys = {}

  invalid_obj = SecureUser.new(email: 'test@example.com', ssn: 'test')
  invalid_obj.save
rescue Familia::EncryptionError => e
  puts "✓ Caught expected error with invalid config: #{e.message}"
ensure
  Familia.config.encryption_keys = old_keys
end

# Test with missing key version
begin
  test_obj = SecureUser.new(email: 'version_test@example.com', ssn: '987-65-4321')
  test_obj.save

  # Simulate missing key version in config
  old_keys = Familia.config.encryption_keys.dup
  Familia.config.encryption_keys = { v3: old_keys[:v2] }

  # This should fail when trying to decrypt
  test_obj.ssn.reveal
rescue Familia::EncryptionError => e
  puts "✓ Caught expected error with missing key version: #{e.message}"
ensure
  Familia.config.encryption_keys = old_keys
end
puts

# Example 7: Benchmarking encryption performance
puts 'Example 7: Encryption performance benchmarks'
if defined?(Familia::Encryption) && Familia::Encryption.respond_to?(:benchmark)
  benchmark_results = Familia::Encryption.benchmark(iterations: 100)

  puts 'Encryption benchmark results (100 iterations):'
  benchmark_results.each do |algorithm, stats|
    puts "  #{algorithm}:"
    puts "    Time: #{(stats[:time] * 1000).round(2)}ms total"
    puts "    Operations/sec: #{stats[:ops_per_sec]}"
    puts "    Priority: #{stats[:priority]}"
  end
else
  puts 'Benchmarking not available in this version'
end
puts

# Example 8: Integration with safe dump feature
class SecureProfile < Familia::Horreum
  feature :encrypted_fields
  feature :safe_dump

  identifier_field :profile_id
  field :profile_id
  field :username                 # Safe to expose
  field :email                    # Safe to expose
  encrypted_field :phone          # Encrypted but can be safely exposed
  encrypted_field :ssn            # Encrypted and should NOT be exposed
  encrypted_field :bank_account   # Encrypted and should NOT be exposed
  field :created_at               # Safe to expose

  # Define safe dump fields - encrypted fields are handled automatically
  safe_dump_field :profile_id
  safe_dump_field :username
  safe_dump_field :email
  safe_dump_field :phone_display, lambda { |profile|
    phone = profile.phone.reveal
    phone ? "#{phone[0..2]}-***-#{phone[-4..]}" : nil
  }
  safe_dump_field :created_at
end

puts 'Example 8: Integration with SafeDump feature'
profile = SecureProfile.new(
  profile_id: 'profile_123',
  username: 'alice_windows',
  email: 'alice@example.com',
  phone: '555-123-4567',
  ssn: '123-45-6789',
  bank_account: '9876543210',
  created_at: Familia.now.to_i
)
profile.save

puts 'Profile safe dump (encrypted fields handled automatically):'
puts JSON.pretty_generate(profile.safe_dump)
puts 'Notice: SSN and bank account are automatically excluded'
puts 'Phone number is included but masked for display'
puts

# Clean up examples
puts '=== Cleaning up test data ==='
[SecureUser, SecureDocument, VaultEntry, RotationTest, MemoryTest, SecureProfile].each do |klass|
  keys = klass.dbclient.keys("#{klass.name.downcase.gsub('::', '_')}:*")
  klass.dbclient.del(*keys) unless keys.empty?
  puts "✓ Cleaned #{klass.name} (#{keys.length} keys)"
rescue StandardError => e
  puts "✗ Error cleaning #{klass.name}: #{e.message}"
end

# Clear any request cache
begin
  Familia::Encryption.clear_request_cache!
rescue StandardError => e
  puts "⚠ Warning: Failed to clear encryption request cache: #{e.message} (#{e.backtrace.join("\n")})"
end

puts
puts '=== Summary ==='
puts 'This example demonstrated:'
puts '• Basic encrypted field usage with transparent access'
puts '• Additional Authenticated Data (AAD) for tamper detection'
puts '• Performance optimization with request-level caching'
puts '• Key rotation procedures and status monitoring'
puts '• Memory safety with ConcealedString and cleanup methods'
puts '• Error handling for configuration and key version issues'
puts '• Encryption performance benchmarking'
puts '• Integration with SafeDump for API-safe serialization'
puts
puts 'Encrypted Fields examples completed!'
