#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing load path and setter behavior..."

class TestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clean database
Familia.dbclient.flushdb

puts "\n=== TRACING THE SETTER DURING LOAD ==="

# First, let's monkey-patch the setter to see what's being called
original_setter = TestModel.instance_method(:secret=)
TestModel.define_method(:secret=) do |value|
  puts "\n--- SETTER CALLED ---"
  puts "Setting secret to: #{value}"
  puts "Value class: #{value.class}"
  puts "Record exists?: #{exists?}"
  puts "Record identifier: #{identifier}"

  if value.is_a?(String) && !value.nil?
    puts "Checking if value is encrypted JSON..."
    field_type = TestModel.field_types[:secret]
    is_encrypted = field_type.encrypted_json?(value)
    puts "encrypted_json? result: #{is_encrypted}"

    if is_encrypted
      puts "Path: Creating ConcealedString WITHOUT re-encryption"
    else
      puts "Path: Will ENCRYPT value and create ConcealedString"
    end
  end
  puts "--- END SETTER ---\n"

  # Call original setter
  original_setter.bind(self).call(value)
end

puts "\nCreating and saving model..."
model = TestModel.new(id: 'test1')
puts "Setting secret on in-memory model..."
model.secret = 'plaintext-secret'

puts "\nSaving model..."
model.save

puts "\nRaw data in database:"
raw_data = Familia.dbclient.hget('testmodel:test1:object', 'secret')
puts "Raw encrypted in DB: #{raw_data[0..100]}..." # Truncate for readability

puts "\n=== LOADING MODEL ==="
loaded_model = TestModel.load('test1')
