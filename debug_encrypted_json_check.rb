#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing encrypted_json? method..."

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

# Test with actual encrypted JSON from the load path
encrypted_json = '{"algorithm":"xchacha20poly1305","nonce":"RDK0GSY3Vbrbv7OAgol10bHOmderAExt","ciphertext":"uo8j6Pm6tV68BcvqK5maXQ==","auth_tag":"5Cr1QgTnajnWIji0fsQP0g==","key_version":"v1"}'

puts "Testing encrypted JSON: #{encrypted_json[0..80]}..."
puts "String class: #{encrypted_json.class}"
puts "Is string?: #{encrypted_json.is_a?(String)}"

puts "\nManual JSON parsing:"
begin
  parsed = JSON.parse(encrypted_json)
  puts "Parsed successfully: #{parsed.class}"
  puts "Is hash?: #{parsed.is_a?(Hash)}"
  puts "Has algorithm key?: #{parsed.key?('algorithm')}"
  puts "Algorithm value: #{parsed['algorithm']}"
rescue => e
  puts "JSON parse error: #{e.class}: #{e.message}"
end

puts "\nTesting field_type.encrypted_json? method:"
result = field_type.encrypted_json?(encrypted_json)
puts "encrypted_json? result: #{result}"

puts "\nTesting with symbol keys:"
begin
  parsed_sym = JSON.parse(encrypted_json, symbolize_names: true)
  puts "Parsed with symbols: #{parsed_sym.class}"
  puts "Has :algorithm key?: #{parsed_sym.key?(:algorithm)}"
  puts "Has 'algorithm' key?: #{parsed_sym.key?('algorithm')}"
rescue => e
  puts "Symbol parse error: #{e.class}: #{e.message}"
end
