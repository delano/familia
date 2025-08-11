#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'

puts "Checking method definition..."

field_type = Familia::EncryptedFieldType.new(:test)
puts "Method source location: #{field_type.method(:encrypted_json?).source_location}"

# Check if the method exists
puts "Method exists?: #{field_type.respond_to?(:encrypted_json?)}"

# Get the method object and examine it
method_obj = field_type.method(:encrypted_json?)
puts "Method object: #{method_obj}"
puts "Method owner: #{method_obj.owner}"

# Call with debugging
puts "\nCalling method..."
result = method_obj.call('{"algorithm":"test"}')
puts "Result: #{result}"

# Let's also check the class directly
puts "\nChecking class method..."
class_result = Familia::EncryptedFieldType.new(:test2).encrypted_json?('{"algorithm":"test"}')
puts "Class result: #{class_result}"

# Try to define the method inline to see if it works
puts "\nDefining method inline..."
field_type.define_singleton_method(:test_encrypted_json?) do |data|
  puts "Inline method called with: #{data}"
  begin
    parsed = JSON.parse(data)
    result = parsed.is_a?(Hash) && parsed.key?('algorithm')
    puts "Inline result: #{result}"
    return result
  rescue => e
    puts "Inline error: #{e}"
    return false
  end
end

inline_result = field_type.test_encrypted_json?('{"algorithm":"test"}')
puts "Inline method result: #{inline_result}"
