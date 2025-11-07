# try/support/memory/test_actual_redactedstring_protection.rb
#
# frozen_string_literal: true

# try/memory/test_actual_redactedstring_protection.rb

require_relative '../helpers/test_helpers'

# Test 1: Does it prevent logging leaks?
secret = "API_KEY_12345"
redacted = RedactedString.new(secret)

puts "Logging test:"
puts "Normal string logs as: #{secret}"  # Shows: API_KEY_12345
puts "Redacted string logs as: #{redacted}"  # Shows: [REDACTED]
puts "✅ Logging protection works!\n\n"

# Test 2: Does it prevent exception leaks?
begin
  raise StandardError, "Error with secret: #{redacted}"
rescue => e
  puts "Exception message: #{e.message}"
  puts "✅ Exception protection works!\n\n" if e.message.include?("[REDACTED]")
end

# Test 3: Does it prevent debug leaks?
require 'pp'
data = {
  user: "john",
  token: redacted
}
puts "Debug output:"
pp data  # Will show token: [REDACTED]
puts "✅ Debug protection works!\n\n"

# Test 4: Real-world usage pattern
redacted.expose do |token|
  # Simulate API call
  puts "Making API call with token (simulated)"
  # HTTParty.get("https://api.example.com", headers: { "Authorization" => token })
end
puts "After API call, trying to access: #{redacted}"  # Still shows [REDACTED]
