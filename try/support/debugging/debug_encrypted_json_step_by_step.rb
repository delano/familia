# try/support/debugging/debug_encrypted_json_step_by_step.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Step-by-step debugging of encrypted_json? method..."

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

# Monkey patch the encrypted_json? method to add debugging
class Familia::EncryptedFieldType
  def encrypted_json?(data)
    puts "\n=== encrypted_json? DEBUG ==="
    puts "Input data: #{data}"
    puts "Data class: #{data.class}"
    puts "Is String?: #{data.is_a?(String)}"

    return false unless data.is_a?(String)
    puts "Passed String check"

    begin
      puts "Attempting JSON.parse..."
      parsed = JSON.parse(data)
      puts "Parsed result: #{parsed}"
      puts "Parsed class: #{parsed.class}"
      puts "Is Hash?: #{parsed.is_a?(Hash)}"

      if parsed.is_a?(Hash)
        puts "Hash keys: #{parsed.keys}"
        puts "Has 'algorithm' key?: #{parsed.key?('algorithm')}"
        result = parsed.key?('algorithm')
        puts "Final result: #{result}"
        return result
      else
        puts "Not a hash, returning false"
        return false
      end
    rescue JSON::ParserError => e
      puts "JSON parse error: #{e.message}"
      false
    end
  end
end

encrypted_json = '{"algorithm":"xchacha20poly1305","nonce":"RDK0GSY3Vbrbv7OAgol10bHOmderAExt","ciphertext":"uo8j6Pm6tV68BcvqK5maXQ==","auth_tag":"5Cr1QgTnajnWIji0fsQP0g==","key_version":"v1"}'

puts "Calling field_type.encrypted_json?..."
result = field_type.encrypted_json?(encrypted_json)
puts "\nFINAL RESULT: #{result}"
