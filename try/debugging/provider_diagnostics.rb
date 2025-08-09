#!/usr/bin/env ruby
# Debug script for testing encryption providers and diagnosing issues

require 'base64'
require_relative '../helpers/test_helpers'

puts "=== Familia Encryption Provider Diagnostics ==="
puts

# Check encryption system status
puts "1. Encryption System Status:"
puts "   Status: #{Familia::Encryption.status.inspect}"
puts

# Check registry setup
puts "2. Registry Providers:"
require_relative '../../lib/familia/encryption/registry'
Familia::Encryption::Registry.setup!
Familia::Encryption::Registry.providers.each do |algo, provider_class|
  puts "   #{algo}: #{provider_class.name}"
  puts "     Available: #{provider_class.available?}"
  puts "     Priority: #{provider_class.priority}"
end
puts

# Setup test keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Test each provider individually
['xchacha20poly1305', 'aes-256-gcm'].each do |algorithm|
  puts "3. Testing #{algorithm.upcase} Provider:"

  begin
    manager = Familia::Encryption::Manager.new(algorithm: algorithm)
    provider = manager.provider

    puts "   Provider class: #{provider.class.name}"
    puts "   Algorithm: #{provider.algorithm}"
    puts "   Nonce size: #{provider.nonce_size} bytes"
    puts "   Auth tag size: #{provider.auth_tag_size} bytes"

    # Test encryption/decryption
    test_data = "diagnostic test data for #{algorithm}"
    encrypted = manager.encrypt(test_data, context: 'diagnostics')
    puts "   Encryption: SUCCESS (#{encrypted.length} chars)"

    decrypted = manager.decrypt(encrypted, context: 'diagnostics')
    success = decrypted == test_data
    puts "   Decryption: #{success ? 'SUCCESS' : 'FAILED'}"

    if !success
      puts "   Expected: #{test_data.inspect}"
      puts "   Got: #{decrypted.inspect}"
    end

  rescue => e
    puts "   ERROR: #{e.class}: #{e.message}"
    puts "   Backtrace: #{e.backtrace.first(3).join(', ')}"
  end

  puts
end

# Test cross-algorithm compatibility
puts "4. Cross-Algorithm Compatibility Test:"
begin
  xchacha_manager = Familia::Encryption::Manager.new(algorithm: 'xchacha20poly1305')
  aes_manager = Familia::Encryption::Manager.new(algorithm: 'aes-256-gcm')
  default_manager = Familia::Encryption::Manager.new

  test_data = "cross-algorithm test"

  # Encrypt with XChaCha20Poly1305
  xchacha_encrypted = xchacha_manager.encrypt(test_data, context: 'cross-test')
  xchacha_decrypted = default_manager.decrypt(xchacha_encrypted, context: 'cross-test')
  puts "   XChaCha20Poly1305 -> Default: #{xchacha_decrypted == test_data ? 'SUCCESS' : 'FAILED'}"

  # Encrypt with AES-GCM
  aes_encrypted = aes_manager.encrypt(test_data, context: 'cross-test')
  aes_decrypted = default_manager.decrypt(aes_encrypted, context: 'cross-test')
  puts "   AES-GCM -> Default: #{aes_decrypted == test_data ? 'SUCCESS' : 'FAILED'}"

rescue => e
  puts "   ERROR: #{e.class}: #{e.message}"
end
puts

# Test high-level API
puts "5. High-Level API Test:"
begin
  encrypted_high = Familia::Encryption.encrypt_with('aes-256-gcm', 'high-level test', context: 'api-test')
  puts "   encrypt_with: SUCCESS"

  # Parse encrypted data to verify structure
  require 'json'
  parsed = JSON.parse(encrypted_high, symbolize_names: true)
  puts "   Algorithm stored: #{parsed[:algorithm]}"
  puts "   Key version: #{parsed[:key_version]}"

  decrypted_high = Familia::Encryption.decrypt(encrypted_high, context: 'api-test')
  puts "   decrypt: #{decrypted_high == 'high-level test' ? 'SUCCESS' : 'FAILED'}"

rescue => e
  puts "   ERROR: #{e.class}: #{e.message}"
end

puts
puts "=== Diagnostics Complete ==="
