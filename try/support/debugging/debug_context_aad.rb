#!/usr/bin/env ruby
# try/support/debugging/debug_context_aad.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Debugging context and AAD generation..."

# Setup encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

class ModelA < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

class ModelB < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :api_key
end

model_a = ModelA.new(id: 'same-id')
model_b = ModelB.new(id: 'same-id')

# Get the field type for each model
field_type_a = ModelA.fields[:api_key]
field_type_b = ModelB.fields[:api_key]

puts "=== Context and AAD Analysis ==="

# Test context generation
context_a = field_type_a.send(:build_context, model_a)
context_b = field_type_b.send(:build_context, model_b)

puts "ModelA context: #{context_a}"
puts "ModelB context: #{context_b}"
puts "Contexts match: #{context_a == context_b}"

# Test AAD generation
aad_a = field_type_a.send(:build_aad, model_a)
aad_b = field_type_b.send(:build_aad, model_b)

puts "\nModelA AAD: #{aad_a}"
puts "ModelB AAD: #{aad_b}"
puts "AADs match: #{aad_a == aad_b}"

puts "\n=== Testing different identifiers ==="
model_a2 = ModelA.new(id: 'different-id')
model_b2 = ModelB.new(id: 'different-id')

context_a2 = field_type_a.send(:build_context, model_a2)
context_b2 = field_type_b.send(:build_context, model_b2)
aad_a2 = field_type_a.send(:build_aad, model_a2)
aad_b2 = field_type_b.send(:build_aad, model_b2)

puts "ModelA2 context: #{context_a2}"
puts "ModelB2 context: #{context_b2}"
puts "A2-B2 contexts match: #{context_a2 == context_b2}"
puts "ModelA2 AAD: #{aad_a2}"
puts "ModelB2 AAD: #{aad_b2}"
puts "A2-B2 AADs match: #{aad_a2 == aad_b2}"
