# try/features/transient_fields/redacted_string_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'


# Create sample sensitive values for testing
@api_key = "sk-1234567890abcdef"
@password = "super_secret_password_123!"
@empty_secret = ""
@long_secret = "a" * 100  # Test long string handling
@special_chars = "päßwörd!@#$%^&*()"

## TEST CASES

## Basic initialization creates RedactedString instance
redacted = RedactedString.new(@api_key)
redacted.class
#=> RedactedString

## Initialization accepts various input types
RedactedString.new("string").class
#=> RedactedString

## Numeric input conversion
RedactedString.new(123).class  # to_s conversion
#=> RedactedString

## Nil input handling
RedactedString.new(nil).class  # nil handling
#=> RedactedString

## Empty string handling
empty_redacted = RedactedString.new(@empty_secret)
empty_redacted.class
#=> RedactedString

## Long string handling
long_redacted = RedactedString.new(@long_secret)
long_redacted.class
#=> RedactedString

## Special characters handling
special_redacted = RedactedString.new(@special_chars)
special_redacted.class
#=> RedactedString

## Fresh instance is not cleared initially
fresh_redacted = RedactedString.new(@api_key)
fresh_redacted.cleared?
#=> false

## to_s always returns redacted placeholder
redacted_for_to_s = RedactedString.new(@api_key)
redacted_for_to_s.to_s
#=> "[REDACTED]"

## inspect returns same as to_s for security
redacted_for_inspect = RedactedString.new(@password)
redacted_for_inspect.inspect
#=> "[REDACTED]"

## String interpolation is redacted
redacted_for_interpolation = RedactedString.new(@api_key)
"Token: #{redacted_for_interpolation}"
#=> "Token: [REDACTED]"

## Array/Hash containing redacted strings show redacted values
redacted_in_array = RedactedString.new(@password)
[redacted_in_array].to_s.include?("[REDACTED]")
#=> true

## expose method requires block
redacted_for_expose_check = RedactedString.new(@api_key)
begin
  redacted_for_expose_check.expose
rescue ArgumentError => e
  e.message
end
#=> "Block required"

## expose method provides access to original value
redacted_for_expose = RedactedString.new("sk-1234567890abcdef")
result = nil
redacted_for_expose.expose { |val| result = val.dup }
result
#=> "sk-1234567890abcdef"

## expose method does not automatically clear after use
redacted_single_use = RedactedString.new(@password)
redacted_single_use.expose { |val| val.length }
redacted_single_use.cleared?
#=> false

## expose method does not clear if exception occurs
redacted_exception_test = RedactedString.new(@api_key)
begin
  redacted_exception_test.expose { |val| raise "test error" }
rescue => e
  # Exception occurred, but string should still be cleared
end
redacted_exception_test.cleared?
#=> false

## expose method on cleared string raises SecurityError
cleared_redacted = RedactedString.new(@password)
cleared_redacted.clear!
begin
  cleared_redacted.expose { |val| val }
rescue SecurityError => e
  e.message
end
#=> "Value already cleared"

## clear! method marks string as cleared
redacted_for_clear = RedactedString.new(@api_key)
redacted_for_clear.clear!
redacted_for_clear.cleared?
#=> true

## clear! method is safe to call multiple times
redacted_multi_clear = RedactedString.new(@password)
redacted_multi_clear.clear!
redacted_multi_clear.clear!  # Second call
redacted_multi_clear.cleared?
#=> true

## clear! method freezes the object
redacted_freeze_test = RedactedString.new(@api_key)
redacted_freeze_test.clear!
redacted_freeze_test.frozen?
#=> true

## Equality comparison only true for same object (prevents timing attacks)
redacted1 = RedactedString.new(@api_key)
redacted2 = RedactedString.new(@api_key)
redacted1 == redacted2
#=> false

## Same object equality returns true
redacted_same = RedactedString.new(@password)
redacted_same == redacted_same
#=> true

## eql? behaves same as ==
redacted_eql1 = RedactedString.new(@api_key)
redacted_eql2 = RedactedString.new(@api_key)
redacted_eql1.eql?(redacted_eql2)
#=> false

## Same object eql? returns true
redacted_eql_same = RedactedString.new(@password)
redacted_eql_same.eql?(redacted_eql_same)
#=> true

## All instances have same hash (prevents hash-based timing attacks)
redacted_hash1 = RedactedString.new(@api_key)
redacted_hash2 = RedactedString.new(@password)
redacted_hash1.hash == redacted_hash2.hash
#=> true

## Hash value is consistent with class hash
redacted_hash_consistent = RedactedString.new(@api_key)
redacted_hash_consistent.hash == RedactedString.hash
#=> true

## RedactedString cannot be used in string operations without expose
redacted_no_concat = RedactedString.new(@api_key)
begin
  result = redacted_no_concat + "suffix"
  false  # Should not reach here
rescue => e
  true   # Expected to raise error
end
#=> true

## RedactedString is not a String subclass (security by design)
redacted_type_check = RedactedString.new(@password)
redacted_type_check.is_a?(String)
#=> false

## Working with empty strings
empty_redacted_test = RedactedString.new("")
result = nil
empty_redacted_test.expose { |val| result = val }
result
#=> ""

## Working with long strings preserves content
long_redacted_test = RedactedString.new("a" * 100)
result = nil
long_redacted_test.expose { |val| result = val.length }
result
#=> 100

## Special characters are preserved
special_redacted_test = RedactedString.new("päßwörd!@#$%^&*()")
result = nil
special_redacted_test.expose { |val| result = val.dup }
result
#=> "päßwörd!@#$%^&*()"

## Finalizer proc exists and is callable
RedactedString.finalizer_proc.class
#=> Proc

## Cleared redacted string maintains redacted appearance
cleared_appearance_test = RedactedString.new(@api_key)
cleared_appearance_test.clear!
cleared_appearance_test.to_s
#=> "[REDACTED]"

## Cleared redacted string inspect still redacted
cleared_inspect_test = RedactedString.new(@password)
cleared_inspect_test.clear!
cleared_inspect_test.inspect
#=> "[REDACTED]"

## Object created from nil input
nil_input_test = RedactedString.new(nil)
result = nil
nil_input_test.expose { |val| result = val.dup }
result
#=> ""

## Numeric input converted to string
numeric_input_test = RedactedString.new(42)
result = nil
numeric_input_test.expose { |val| result = val.dup }
result
#=> "42"

## Symbol input converted to string
symbol_input_test = RedactedString.new(:secret)
result = nil
symbol_input_test.expose { |val| result = val.dup }
result
#=> "secret"


# TEARDOWN

# Clean up any remaining test objects
@api_key = nil
@password = nil
@empty_secret = nil
@long_secret = nil
@special_chars = nil

# Force garbage collection to trigger any finalizers
GC.start
