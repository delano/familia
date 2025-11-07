# try/support/debugging/debug_minimal.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
require 'familia'

# Minimal test
field_type = Familia::EncryptedFieldType.new(:test)
json = '{"algorithm":"test"}'

puts "Testing: #{json}"
puts "Result: #{field_type.encrypted_json?(json)}"

# Manual implementation
puts "\nManual check:"
begin
  parsed = JSON.parse(json)
  puts "Parsed: #{parsed}"
  puts "Is hash?: #{parsed.is_a?(Hash)}"
  puts "Has algorithm?: #{parsed.key?('algorithm')}"
  result = parsed.is_a?(Hash) && parsed.key?('algorithm')
  puts "Manual result: #{result}"
rescue => e
  puts "Error: #{e}"
end
