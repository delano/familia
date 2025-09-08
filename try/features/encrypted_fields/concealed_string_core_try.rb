# try/features/encryption_fields/concealed_string_core_try.rb

require_relative '../../helpers/test_helpers'
require 'base64'

Familia.debug = false

# Configure encryption keys
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Test class with encrypted fields
class TestSecretDocument < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  field :title                    # Regular field for comparison
  encrypted_field :content        # This will use ConcealedString
  encrypted_field :api_key        # Another encrypted field
end

# Assign it to the global namespace for proper naming
Object.const_set(:SecretDocument, TestSecretDocument)

# Clean test environment
Familia.dbclient.flushdb

# Create test document
@doc = SecretDocument.new
@doc.id = "test123"
@doc.title = "Public Title"
@doc.content = "secret information"
@doc.api_key = "sk-1234567890"

## Basic ConcealedString creation
@doc.content.class.name
#=> "ConcealedString"

## API key also returns ConcealedString
@doc.api_key.class.name
#=> "ConcealedString"

## Reveal API - controlled decryption
revealed_content = nil
@doc.content.reveal do |plaintext|
  revealed_content = plaintext
end
revealed_content
#=> "secret information"

## Reveal can be called multiple times
revealed_again = nil
@doc.content.reveal do |plaintext|
  revealed_again = plaintext
end
revealed_again
#=> "secret information"

## Reveal requires block argument
begin
  @doc.content.reveal  # No block provided
rescue ArgumentError => e
  e.message
end
#=> "Block required for reveal"

## Universal Serialization Safety - to_s
@doc.content.to_s
#=> "[CONCEALED]"

## inspect method
@doc.content.inspect
#=> "[CONCEALED]"

## to_str method should not exist for security (implicit string conversion)
@doc.content.to_str
#=!> NoMethodError

## JSON serialization - to_json (fails for security)
begin
  @doc.content.to_json
  raise "Should have raised SerializerError"
rescue Familia::SerializerError => e
  e.class
end
#=> Familia::SerializerError

## JSON serialization - as_json
@doc.content.as_json
#=> "[CONCEALED]"

## Hash conversion
@doc.content.to_h
#=> "[CONCEALED]"

## Array conversion
@doc.content.to_a
#=> ["[CONCEALED]"]

## String concatenation safety
(@doc.content + " extra")
#=> "[CONCEALED]"

## Length operation
@doc.content.length
#=> 11

## Empty check
@doc.content.empty?
#=> false

## Present check
@doc.content.present?
#=> true

## Equality operations - different objects not equal
@content1 = @doc.content
@content2 = @doc.api_key
(@content1 == @content2)
#=> false

## Same object equality
(@content1 == @content1)
#=> true

## Hash consistency for timing attack prevention
(@content1.hash == @content2.hash)
#=> true

## Pattern matching - deconstruct
@doc.content.deconstruct
#=> ["[CONCEALED]"]

## Pattern matching - deconstruct_keys
@doc.content.deconstruct_keys([])
#=:> Hash

## Enumeration safety
@doc.content.map { |x| x.upcase }
#=> ["[CONCEALED]"]

## Encrypted data access for storage
@encrypted_data = @doc.content.encrypted_value
@encrypted_data
#=:> String

## Encrypted data is valid JSON
begin
  parsed = JSON.parse(@encrypted_data)
  parsed.key?('algorithm')
rescue
  false
end
#=> true

## Memory clearing functionality
# Create a separate document for clearing tests to avoid affecting other tests
@clear_doc = SecretDocument.new
@clear_doc.id = "clear_test"
@clear_doc.content = "data to be cleared"
@test_concealed = @clear_doc.content
@test_concealed.cleared?
#=> false

## Clear operation
@test_concealed.clear!
@test_concealed.cleared?
#=> true

## After clearing, reveal raises error
begin
  @test_concealed.reveal { |x| x }
rescue SecurityError => e
  e.message
end
#=> "Encrypted data already cleared"

## String interpolation safety
interpolated = "Content: #{@doc.content}"
interpolated
#=> "Content: [CONCEALED]"

## Array inclusion safety
debug_array = [@doc.title, @doc.content, @doc.api_key]
debug_array.map(&:to_s)
#=> ["Public Title", "[CONCEALED]", "[CONCEALED]"]

## Database persistence - debug serialization
@storage_hash = @doc.to_h_for_storage
@storage_hash.keys
#=> ["id", "title", "content", "api_key"]

## Save document with encrypted fields
@save_result1 = @doc.save
@save_result1
#=> true

## After saving, re-encrypt with proper AAD context
@doc.content = "secret information"  # Re-encrypt now that record exists
@save_result2 = @doc.save
@save_result2
#=> true

## After saving, behavior is identical
@doc.content.to_s
#=> "[CONCEALED]"

## Post-save reveal works
@doc.content.reveal { |x| x }
#=> "secret information"

## Fresh load from database
@fresh_doc = SecretDocument.load("test123")
@fresh_doc&.content&.class&.name || "nil or missing"
#=> "ConcealedString"

## Debug what's actually in the database
@all_keys = Familia.dbclient.keys("*")
@all_keys
#=> ["secretdocument:test123:object"]

## Check database storage - should be encrypted
@db_hash = Familia.dbclient.hgetall("secretdocument:test123:object")
@db_hash.keys
#=> ["id", "title", "content", "api_key"]

## Database storage contains encrypted string
db_content = Familia.dbclient.hget("secretdocument:test123:object", "content")
db_content&.class&.name || "nil"
#=> "String"

## Fresh load reveal works (if content exists)
if @fresh_doc&.content.respond_to?(:reveal)
  begin
    @fresh_doc.content.reveal { |x| x }
  rescue => e
    "DECRYPTION ERROR: #{e.class}: #{e.message}"
  end
else
  "content is nil or missing"
end
#=> "secret information"

## Regular fields unaffected
@doc.title
#=:> String

## Regular field access
@doc.title
#=> "Public Title"

## Mixed field operations
(@doc.title + " has concealed content")
#=> "Public Title has concealed content"

# Teardown
Familia.dbclient.flushdb
