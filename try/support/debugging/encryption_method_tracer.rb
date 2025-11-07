# try/support/debugging/encryption_method_tracer.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby
# Debug script to trace encryption method calls and data flow

require 'base64'
require 'bundler/setup'
require_relative '../helpers/test_helpers'

puts "=== Encryption Method Call Tracer ==="
puts

# Monkey patch to add detailed tracing
module Familia
  module Encryption
    class << self
      # Store original methods
      alias_method :orig_encrypt, :encrypt
      alias_method :orig_decrypt, :decrypt

      def encrypt(plaintext, context:, additional_data: nil)
        puts "📤 ENCRYPT called:"
        puts "   Context: #{context}"
        puts "   Plaintext length: #{plaintext&.length} chars"
        puts "   AAD: #{additional_data ? 'present' : 'none'}"

        start_time = Familia.now
        result = orig_encrypt(plaintext, context: context, additional_data: additional_data)
        elapsed = ((Familia.now - start_time) * 1000).round(2)

        puts "   Result length: #{result ? result.length : 'nil'} chars"
        puts "   Elapsed: #{elapsed}ms"
        puts
        result
      end

      def decrypt(encrypted_json, context:, additional_data: nil)
        puts "📥 DECRYPT called:"
        puts "   Context: #{context}"
        puts "   Encrypted length: #{encrypted_json&.length} chars"
        puts "   AAD: #{additional_data ? 'present' : 'none'}"

        start_time = Familia.now
        begin
          result = orig_decrypt(encrypted_json, context: context, additional_data: additional_data)
          elapsed = ((Familia.now - start_time) * 1000).round(2)

          puts "   Result length: #{result ? result.length : 'nil'} chars"
          puts "   Elapsed: #{elapsed}ms"
          puts
          result
        rescue => e
          elapsed = ((Familia.now - start_time) * 1000).round(2)
          puts "   ERROR: #{e.class}: #{e.message}"
          puts "   Elapsed: #{elapsed}ms"
          puts
          raise
        end
      end
    end

    class Manager
      alias_method :orig_derive_key_with_provider, :derive_key_with_provider

      def derive_key_with_provider(provider, context, version: nil)
        puts "🔑 DERIVE_KEY called:"
        puts "   Provider: #{provider.class.name}"
        puts "   Context: #{context}"
        puts "   Version: #{version || 'current'}"

        cache = Fiber[:familia_key_cache] ||= {}
        cache_key = "#{version || current_key_version}:#{context}"
        puts "   Cache key: #{cache_key}"
        puts "   Cache before: #{cache.keys.inspect}"

        start_time = Familia.now
        result = orig_derive_key_with_provider(provider, context, version: version)
        elapsed = ((Familia.now - start_time) * 1000).round(2)

        cache_after = Fiber[:familia_key_cache] || {}
        puts "   Cache after: #{cache_after.keys.inspect}"
        puts "   Derived key: [#{result.bytesize} bytes]"
        puts "   Elapsed: #{elapsed}ms"
        puts
        result
      end
    end
  end
end

# Setup test configuration
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clear cache
Fiber[:familia_key_cache] = nil

# Define test model
class TraceTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  encrypted_field :password
  encrypted_field :api_key, aad_fields: [:user_id]
end

puts "=== Test Scenario: Field Operations ==="
puts

puts "Creating model and setting encrypted fields..."
user = TraceTestModel.new(user_id: 'trace-user-1')

puts "Setting password (no AAD)..."
user.password = 'secret-password-123'

puts "Setting api_key (with AAD)..."
user.api_key = 'api-key-xyz-789'

puts "Reading password..."
retrieved_password = user.password
puts "Final password value: #{retrieved_password}"

puts "Reading api_key..."
retrieved_api_key = user.api_key
puts "Final api_key value: #{retrieved_api_key}"

puts
puts "=== Test Scenario: Cross-Algorithm Decryption ==="
puts

# Test cross-algorithm compatibility
aes_encrypted = Familia::Encryption.encrypt_with('aes-256-gcm', 'cross-test-data', context: 'cross-test')
puts "Decrypting AES-GCM data with default manager..."
cross_decrypted = Familia::Encryption.decrypt(aes_encrypted, context: 'cross-test')
puts "Cross-algorithm result: #{cross_decrypted}"

puts
puts "=== Method Tracing Complete ==="
