#!/usr/bin/env ruby
# try/support/debugging/debug_database_load.rb
#
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'  # Mark as test environment
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Testing database load vs in-memory encryption..."

class TestModel < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :title
  encrypted_field :secret
end

test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Clean database
Familia.dbclient.flushdb

puts "\n=== PHASE 1: In-memory object ==="
model = TestModel.new(id: 'test1')
model.title = 'Test Title'
puts "PRE-ENCRYPT: model.exists? = #{model.exists?}"
model.secret = 'plaintext-secret'

puts "In-memory secret class: #{model.secret.class}"
puts "In-memory secret value: #{model.secret}"

model.secret.reveal do |plaintext|
  puts "In-memory reveal: #{plaintext}"
end

puts "\n=== PHASE 2: Save to database ==="
model.save

puts "Keys in database: #{Familia.dbclient.keys('*')}"
puts "Hash contents: #{Familia.dbclient.hgetall('testmodel:test1:object')}"

raw_secret = Familia.dbclient.hget('testmodel:test1:object', 'secret')
puts "Raw secret from DB: #{raw_secret}"

puts "\n=== PHASE 3: Load from database ==="
loaded_model = TestModel.load('test1')

if loaded_model
  puts "Loaded model exists: #{loaded_model.exists?}"
  puts "Loaded secret class: #{loaded_model.secret.class}"
  puts "Loaded secret value: #{loaded_model.secret}"

  begin
    loaded_model.secret.reveal do |plaintext|
      puts "Loaded reveal: #{plaintext}"
    end
  rescue => e
    puts "Loaded reveal ERROR: #{e.class}: #{e.message}"
  end
else
  puts "Failed to load model"
end
