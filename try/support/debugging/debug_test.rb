#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing ConcealedString reveal_for_testing method..."

class TestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

Familia.config.encryption_keys = { v1: SecureRandom.hex(32) }
Familia.config.current_key_version = :v1

model = TestModel.new(id: 'test1')
model.secret = 'plaintext-secret'

puts "Setting secret to: plaintext-secret"
puts "Class of secret field: #{model.secret.class}"
puts "Secret field value: #{model.secret}"

if model.secret.respond_to?(:reveal_for_testing)
  puts "Attempting reveal_for_testing..."
  begin
    decrypted = model.secret.reveal_for_testing
    puts "reveal_for_testing result: #{decrypted}"
  rescue => e
    puts "reveal_for_testing failed: #{e.class}: #{e.message}"
  end
end

if model.secret.respond_to?(:reveal)
  puts "Attempting reveal block..."
  begin
    model.secret.reveal do |decrypted|
      puts "reveal block result: #{decrypted}"
    end
  rescue => e
    puts "reveal block failed: #{e.class}: #{e.message}"
  end
end
