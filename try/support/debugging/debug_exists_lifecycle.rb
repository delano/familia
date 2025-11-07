# try/support/debugging/debug_exists_lifecycle.rb
#
# frozen_string_literal: true

#!/usr/bin/env ruby

$LOAD_PATH.unshift(File.expand_path('lib', __dir__))
ENV['TEST'] = 'true'
require 'familia'
require_relative 'try/helpers/test_helpers'

puts "Investigating exists? lifecycle..."

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

# Override the exists? method to add logging
class TestModel
  alias_method :original_exists?, :exists?
  def exists?
    result = original_exists?
    puts "EXISTS? called - result: #{result} (identifier: #{identifier})" if ENV['TEST']
    result
  end
end

puts "\n=== CREATION AND SAVE ==="
model = TestModel.new(id: 'test1')
puts "After new - exists?: #{model.exists?}"
model.secret = 'plaintext-secret'
puts "After setting secret - exists?: #{model.exists?}"
model.save
puts "After save - exists?: #{model.exists?}"

puts "\n=== LOAD FROM DATABASE ==="
puts "About to load..."
loaded_model = TestModel.load('test1')
puts "After load - exists?: #{loaded_model.exists?}"

puts "\n=== TRYING TO ACCESS SECRET ==="
begin
  loaded_model.secret.reveal do |plaintext|
    puts "Successfully revealed: #{plaintext}"
  end
rescue => e
  puts "Failed to reveal: #{e.class}: #{e.message}"
end
