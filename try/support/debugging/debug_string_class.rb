# try/support/debugging/debug_string_class.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'

puts "Investigating the string class issue..."

field_type = Familia::EncryptedFieldType.new(:test)
json = '{"algorithm":"test"}'

puts "Testing string object:"
puts "json: #{json}"
puts "json.class: #{json.class}"
puts "json.is_a?(String): #{json.is_a?(String)}"
puts "json.kind_of?(String): #{json.kind_of?(String)}"
puts "json.class == String: #{json.class == String}"
puts "json.class.ancestors: #{json.class.ancestors}"

# Let's test with various string types
frozen_string = '{"algorithm":"test"}'.freeze
puts "\nTesting frozen string:"
puts "frozen.class: #{frozen_string.class}"
puts "frozen.is_a?(String): #{frozen_string.is_a?(String)}"

# Test with different string creation methods
string_new = String.new('{"algorithm":"test"}')
puts "\nTesting String.new:"
puts "string_new.class: #{string_new.class}"
puts "string_new.is_a?(String): #{string_new.is_a?(String)}"

# Let's inspect what the method actually receives
puts "\nTesting what the method actually receives..."
field_type.define_singleton_method(:debug_encrypted_json?) do |data|
  puts "Received data: #{data.inspect}"
  puts "Data class: #{data.class}"
  puts "Data class ancestors: #{data.class.ancestors}"
  puts "Is String?: #{data.is_a?(String)}"
  puts "Kind of String?: #{data.kind_of?(String)}"
  puts "Equals String class?: #{data.class == String}"
  puts "Responds to string methods?: #{data.respond_to?(:upcase)}"
  return "debug_complete"
end

result = field_type.debug_encrypted_json?(json)
puts "Debug result: #{result}"
