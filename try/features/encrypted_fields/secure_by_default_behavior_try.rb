# try/features/encrypted_fields/secure_by_default_behavior_try.rb
#
# frozen_string_literal: true

# try/features/encryption_fields/secure_by_default_behavior_try.rb

require_relative '../../support/helpers/test_helpers'
require 'base64'

Familia.debug = false

# Configure encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Test class demonstrating secure patterns
class SecureUserAccount < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :username                      # Public field
  field :email                         # Public field
  encrypted_field :password_hash       # Secure field
  encrypted_field :api_secret          # Secure field
  encrypted_field :recovery_key        # Secure field
end

# Clean test environment
Familia.dbclient.flushdb

# Create test user
@user = SecureUserAccount.new
@user.id = "user123"
@user.username = "john_doe"
@user.email = "john@example.com"
@user.password_hash = "bcrypt$2a$12$abcdef..."
@user.api_secret = "sk-1234567890abcdef"
@user.recovery_key = "recovery-key-xyz789"

## Public field returns String class and value
@user.username
#=:> String
#=> "john_doe"

## Email field returns correct value
@user.email
#=> "john@example.com"

## Password hash returns ConcealedString - no auto-decryption
@user.password_hash.class.name
#=> "ConcealedString"

## API secret returns ConcealedString
@user.api_secret.class.name
#=> "ConcealedString"

## Recovery key returns ConcealedString
@user.recovery_key.class.name
#=> "ConcealedString"

## Explicit reveal required for password access
revealed_password = nil
@user.password_hash.reveal do |plaintext|
  revealed_password = plaintext
end
revealed_password
#=> "bcrypt$2a$12$abcdef..."

## Multiple encrypted fields require individual reveals
revealed_secret = nil
@user.api_secret.reveal do |plaintext|
  revealed_secret = plaintext
end
revealed_secret
#=> "sk-1234567890abcdef"

## String operations on encrypted fields are safe
password_string = @user.password_hash.to_s
password_string.include?("bcrypt")
#=> false

## to_s returns concealed marker
@user.password_hash.to_s
#=> "[CONCEALED]"

## inspect is safe for debugging
inspect_result = @user.password_hash.inspect
inspect_result.include?("bcrypt")
#=> false

## inspect returns concealed marker
@user.password_hash.inspect
#=> "[CONCEALED]"

## Array operations are secure
all_fields = [@user.username, @user.password_hash, @user.api_secret]
field_strings = all_fields.map(&:to_s)
field_strings
#=> ["john_doe", "[CONCEALED]", "[CONCEALED]"]

## Hash serialization excludes encrypted fields
user_hash = @user.to_h
user_hash.keys.include?("password_hash")
#=> false

## API secret also excluded from serialization
@user.to_h.keys.include?("api_secret")
#=> false

## Recovery key excluded from serialization
@user.to_h.keys.include?("recovery_key")
#=> false

## Only public fields included in serialization
@user.to_h.keys.sort
#=> ["email", "id", "username"]

## Database operations preserve security
@user.save
#=> true

## Fresh load from database returns ConcealedString
@fresh_user = SecureUserAccount.load("user123")
@fresh_user.password_hash.class.name
#=> "ConcealedString"

## Fresh user API secret is concealed
@fresh_user.api_secret.class.name
#=> "ConcealedString"

## Plaintext still requires explicit reveal after reload
revealed_fresh = nil
@fresh_user.password_hash.reveal do |plaintext|
  revealed_fresh = plaintext
end
revealed_fresh
#=> "bcrypt$2a$12$abcdef..."

## Regular field string operations work normally
@user.username.upcase
#=> "JOHN_DOE"

## Regular field length access
@user.username.length
#=> 8

## Regular field substring access
@user.username[0..3]
#=> "john"

## Encrypted field string operations are protected
@user.password_hash.upcase
#=> "[CONCEALED]"

## Encrypted field length is concealed length
@user.password_hash.length
#=> 11

## Encrypted field substring is from concealed text
@user.password_hash.to_s[0..3]
#=> "[CON"

## Logging patterns are safe
@log_message = "User #{@user.username} with password #{@user.password_hash}"
@log_message.include?("bcrypt")
#=> false

## Log message shows concealed value
@log_message
#=> "User john_doe with password [CONCEALED]"

## Exception messages are safe
begin
  raise StandardError, "Authentication failed for #{@user.password_hash}"
rescue StandardError => e
  e.message.include?("bcrypt")
end
#=> false

## String method chaining is safe
transformed = @user.password_hash.downcase.strip.gsub(/secret/, "public")
transformed
#=> "[CONCEALED]"

## Concatenation fails safely without to_str method (prevents accidental implicit conversion)
begin
  @combined = "Password: " + @user.password_hash + " (encrypted)"
  "concatenation_should_fail"
rescue TypeError => e
  e.message.include?("no implicit conversion")
end
#=> true

## JSON serialization prevents leakage by raising error
begin
  user_json = Familia::JsonSerializer.dump({
    id: @user.id,
    username: @user.username,
    password: @user.password_hash
  })
  false
rescue Familia::SerializerError
  true
end
#=> true

## JSON serialization with ConcealedString raises error
begin
  user_json = Familia::JsonSerializer.dump({
    id: @user.id,
    username: @user.username,
    password: @user.password_hash
  })
  false
rescue Familia::SerializerError => e
  e.message.include?("ConcealedString")
end
#=> true

## Bulk field operations are secure
@encrypted_fields = [:password_hash, :api_secret, :recovery_key]
@field_values = @encrypted_fields.map { |field| @user.send(field) }

@field_values.all? { |val| val.class.name == "ConcealedString" }
#=> true

## All serialize safely
@safe_strings = @field_values.map(&:to_s)
@safe_strings.all? { |str| str == "[CONCEALED]" }
#=> true

## Conditional operations are safe
password_present = @user.password_hash.present?
password_present
#=> true

## Empty check is safe
password_empty = @user.password_hash.empty?
password_empty
#=> false

## Nil check works
(@user.password_hash.nil?)
#=> false

## Assignment maintains security
@user.api_secret = "new-secret-key-456"
@user.api_secret.class.name
#=> "ConcealedString"

## New assignment serializes safely
@user.api_secret.to_s
#=> "[CONCEALED]"

## Updating with reveal access to old value
old_value = nil
new_value = "updated-secret-789"

@user.api_secret.reveal do |current|
  old_value = current
  @user.api_secret = new_value
end

old_value
#=> "new-secret-key-456"

## Updated value accessible via reveal
@user.api_secret.reveal { |x| x }
#=> "updated-secret-789"

## Nil assignment returns nil
@user.recovery_key = nil
@user.recovery_key
#=> nil

## Nil encrypted fields are NilClass
@user.recovery_key.class.name
#=> "NilClass"

## Setting back to value returns to ConcealedString
@user.recovery_key = "new-recovery-key"
@user.recovery_key.class.name
#=> "ConcealedString"

## Common mistake patterns are secure - string interpolation
search_pattern = "password_hash:#{@user.password_hash}"
search_pattern.include?("bcrypt")
#=> false

## API response safety
api_response = {
  user_id: @user.id,
  credentials: {
    password: @user.password_hash,
    api_key: @user.api_secret
  }
}

begin
  @response_json = Familia::JsonSerializer.dump(api_response)
  false
rescue Familia::SerializerError
  true
end
#=> true

## API response doesn't leak secrets
api_response = {
  user_id: @user.id,
  credentials: {
    password: @user.password_hash,
    api_key: @user.api_secret
  }
}

begin
  @response_json = Familia::JsonSerializer.dump(api_response)
  false
rescue Familia::SerializerError
  true
end
#=> true

## API response contains concealed markers
api_response = {
  user_id: @user.id,
  credentials: {
    password: @user.password_hash,
    api_key: @user.api_secret
  }
}

begin
  @response_json = Familia::JsonSerializer.dump(api_response)
  false
rescue Familia::SerializerError => e
  e.message.include?("ConcealedString")
end
#=> true

## Debug logging safety
@debug_values = @user.instance_variables.map do |var|
  "#{var}=#{@user.instance_variable_get(var)}"
end

@debug_string = @debug_values.join(", ")
@debug_string.include?("bcrypt")
#=> false

## Debug output contains concealed markers
@debug_string.include?("[CONCEALED]")
#=> true

# Teardown
Familia.dbclient.flushdb
