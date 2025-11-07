#!/usr/bin/env ruby
# try/support/debugging/debug_method_resolution.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing method resolution for encrypted_json?..."

class TestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

field_type = TestModel.field_types[:secret]
encrypted_json = '{"algorithm":"xchacha20poly1305","nonce":"test","ciphertext":"test","auth_tag":"test","key_version":"v1"}'

puts "Field type class: #{field_type.class}"
puts "Field type method location: #{field_type.method(:encrypted_json?).source_location}"

# Test the method directly
puts "\nDirect method test:"
puts "Result: #{field_type.encrypted_json?(encrypted_json)}"

# Test with a fresh instance
puts "\nCreating fresh EncryptedFieldType instance:"
fresh_field_type = Familia::EncryptedFieldType.new(:test)
puts "Fresh field type method location: #{fresh_field_type.method(:encrypted_json?).source_location}"
puts "Fresh instance result: #{fresh_field_type.encrypted_json?(encrypted_json)}"

# Test with simple JSON
simple_json = '{"algorithm":"test"}'
puts "\nTesting with simple JSON: #{simple_json}"
puts "Field type result: #{field_type.encrypted_json?(simple_json)}"
puts "Fresh instance result: #{fresh_field_type.encrypted_json?(simple_json)}"
