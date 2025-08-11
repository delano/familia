# try/features/encryption_fields/universal_serialization_safety_try.rb

require_relative '../../helpers/test_helpers'
require 'base64'

Familia.debug = false

# Configure encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Test class with mixed field types
class DataRecord < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :title                        # Public field
  field :description                  # Public field
  encrypted_field :api_token          # Encrypted field
  encrypted_field :secret_notes       # Encrypted field
  encrypted_field :user_data          # Encrypted field
end

# Clean environment
Familia.dbclient.flushdb

# Create test record with mixed data
@record = DataRecord.new
@record.id = "rec001"
@record.title = "Public Record"
@record.description = "This is public information"
@record.api_token = "token-abc123456789"
@record.secret_notes = "confidential information"
@record.user_data = "sensitive user details"

## Object-level to_h excludes encrypted fields
hash_result = @record.to_h
hash_result.keys.include?("api_token")
#=> false

## to_h excludes secret notes
@record.to_h.keys.include?("secret_notes")
#=> false

## to_h excludes user data
@record.to_h.keys.include?("user_data")
#=> false

## to_h only includes public fields
@record.to_h.keys.sort
#=> ["description", "id", "title"]

## to_h contains correct public values
@record.to_h["title"]
#=> "Public Record"

## Individual encrypted field serialization safety - to_s
@record.api_token.to_s
#=> "[CONCEALED]"

## to_str serialization
@record.api_token.to_str
#=> "[CONCEALED]"

## inspect serialization
@record.api_token.inspect
#=> "[CONCEALED]"

## JSON serialization - to_json
@record.api_token.to_json
#=> "\"[CONCEALED]\""

## JSON serialization - as_json
@record.api_token.as_json
#=> "[CONCEALED]"

## Hash serialization
@record.api_token.to_h
#=> "[CONCEALED]"

## Array serialization
@record.api_token.to_a
#=> ["[CONCEALED]"]

## Numeric serialization - to_i
@record.api_token.to_i
#=> 0

## Float serialization
@record.api_token.to_f
#=> 0.0

## Complex nested JSON structure
@nested_data = {
  record: @record,
  fields: {
    public: [@record.title, @record.description],
    encrypted: [@record.api_token, @record.secret_notes]
  }
}

@serialized = @nested_data.to_json
@serialized.include?("token-abc123456789")
#=> false

## Nested JSON contains concealed markers
@nested_data.to_json.include?("[CONCEALED]")
#=> true

## Array of mixed field types safety
@mixed_array = [
  @record.title,
  @record.api_token,
  @record.description,
  @record.secret_notes
]

@mixed_array.to_json.include?("token-abc123456789")
#=> false

## Mixed array preserves public data
@mixed_array.to_json.include?("Public Record")
#=> true

## String interpolation safety
@debug_message = "Record #{@record.id}: token=#{@record.api_token}"
@debug_message.include?("token-abc123456789")
#=> false

## Interpolation shows concealed values
@debug_message.include?("[CONCEALED]")
#=> true

## Hash merge operations safety
merged_hash = @record.to_h.merge({
  runtime_token: @record.api_token
})

merged_hash.values.any? { |v| v.to_s.include?("token-abc123456789") }
#=> false

## Database persistence maintains safety
@record.save
#=> true

## Fresh load serialization safety
@fresh_record = DataRecord.load("rec001")
@fresh_record.to_h.keys.include?("api_token")
#=> false

## Fresh record field safety
@fresh_record.api_token.to_s
#=> "[CONCEALED]"

## Exception handling safety
begin
  raise StandardError, "Auth failed: #{@record.api_token}"
rescue StandardError => e
  e.message.include?("token-abc123456789")
end
#=> false

## String formatting safety
@formatted = "Token: %s" % [@record.api_token]
@formatted.include?("token-abc123456789")
#=> false

## Formatted string shows concealed
@formatted.include?("[CONCEALED]")
#=> true

# Teardown
Familia.dbclient.flushdb
