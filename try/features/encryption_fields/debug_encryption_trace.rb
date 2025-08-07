#!/usr/bin/env ruby

# Debug script to trace encryption method calls

require 'bundler/setup'
require_relative 'lib/familia'
require 'base64'

# Monkey patch to add tracing
module Familia
  module Encryption
    class << self
      alias_method :orig_encrypt, :encrypt
      alias_method :orig_decrypt, :decrypt
      alias_method :orig_derive_key, :derive_key

      def encrypt(plaintext, context:, additional_data: nil)
        puts "ENCRYPT called: context=#{context}, plaintext_len=#{plaintext&.length}"
        result = orig_encrypt(plaintext, context: context, additional_data: additional_data)
        puts "ENCRYPT result: #{result ? result.length : 'nil'} chars"
        result
      end

      def decrypt(encrypted_json, context:, additional_data: nil)
        puts "DECRYPT called: context=#{context}, encrypted_len=#{encrypted_json&.length}"
        result = orig_decrypt(encrypted_json, context: context, additional_data: additional_data)
        puts "DECRYPT result: #{result ? result.length : 'nil'} chars"
        result
      end

      def derive_key(context, version: nil)
        puts "DERIVE_KEY called: context=#{context}, version=#{version}"
        cache = key_cache
        cache_key = "#{version || current_key_version}:#{context}"
        puts "  Cache key: #{cache_key}"
        puts "  Cache before: #{cache.inspect}"

        result = orig_derive_key(context, version: version)

        puts "  Cache after: #{cache.inspect}"
        puts "  Derived key: [#{result.bytesize} bytes]"
        result
      end
    end
  end
end

# Setup test configuration
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clear any existing cache
Thread.current[:familia_key_cache] = nil

# Define test model
class TraceTestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id

  field :user_id
  encrypted_field :password
end

puts "=== Creating model and setting encrypted field ==="
user = TraceTestModel.new(user_id: 'user1')
user.password = 'test-password'

puts "\n=== Getting encrypted field ==="
retrieved = user.password
puts "Final retrieved value: #{retrieved}"
