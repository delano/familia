#!/usr/bin/env ruby
# try/support/debugging/debug_context_simple.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'

puts "Understanding the issue with cross-context decryption..."

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

puts "ModelA class: #{model_a.class}"
puts "ModelB class: #{model_b.class}"
puts "Same class?: #{model_a.class == model_b.class}"

# Inspect what context would be built
puts "\nContext analysis:"
puts "ModelA identifier: #{model_a.identifier}"
puts "ModelB identifier: #{model_b.identifier}"

# Let's see what happens with the field types
modelA_api_key_type = nil
modelB_api_key_type = nil

ModelA.field_types.each do |name, type|
  if name == :api_key
    modelA_api_key_type = type
    break
  end
end

ModelB.field_types.each do |name, type|
  if name == :api_key
    modelB_api_key_type = type
    break
  end
end

puts "ModelA api_key type: #{modelA_api_key_type}"
puts "ModelB api_key type: #{modelB_api_key_type}"
puts "Same type object?: #{modelA_api_key_type.object_id == modelB_api_key_type.object_id}"

# Check what context and AAD would be generated
if modelA_api_key_type && modelB_api_key_type
  context_a = "#{model_a.class.name}:api_key:#{model_a.identifier}"
  context_b = "#{model_b.class.name}:api_key:#{model_b.identifier}"

  puts "\nExpected contexts:"
  puts "ModelA context: #{context_a}"
  puts "ModelB context: #{context_b}"
  puts "Contexts should be different: #{context_a != context_b}"

  # AAD should be identifier when no aad_fields
  aad_a = model_a.identifier
  aad_b = model_b.identifier

  puts "\nExpected AADs:"
  puts "ModelA AAD: #{aad_a}"
  puts "ModelB AAD: #{aad_b}"
  puts "AADs are same: #{aad_a == aad_b}"
end
