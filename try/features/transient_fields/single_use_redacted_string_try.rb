# try/features/transient_fields/single_use_redacted_string_try.rb

require_relative '../../helpers/test_helpers'

@otp_code = "123456"
@auth_token = "temp-auth-token-xyz"
@encryption_key = "encryption-key-abc123"
@empty_secret = ""
@long_secret = "x" * 50  # Test long string handling
@special_chars = "tëmp!@#$%"

## Basic initialization creates SingleUseRedactedString instance
single_use = SingleUseRedactedString.new(@otp_code)
single_use.class
#=> SingleUseRedactedString

## SingleUseRedactedString inherits from RedactedString
single_use_inheritance = SingleUseRedactedString.new(@auth_token)
single_use_inheritance.is_a?(RedactedString)
#=> true

## Initialization accepts various input types
SingleUseRedactedString.new("string").class
#=> SingleUseRedactedString

SingleUseRedactedString.new(123).class  # to_s conversion
#=> SingleUseRedactedString

SingleUseRedactedString.new(nil).class  # nil handling
#=> SingleUseRedactedString

## Fresh instance is not cleared initially
fresh_single_use = SingleUseRedactedString.new(@otp_code)
fresh_single_use.cleared?
#=> false

## to_s returns redacted placeholder (inherited behavior)
single_use_to_s = SingleUseRedactedString.new(@auth_token)
single_use_to_s.to_s
#=> "[REDACTED]"

## inspect returns same as to_s (inherited behavior)
single_use_inspect = SingleUseRedactedString.new(@encryption_key)
single_use_inspect.inspect
#=> "[REDACTED]"

## String interpolation is redacted (inherited behavior)
single_use_interpolation = SingleUseRedactedString.new(@otp_code)
"OTP: #{single_use_interpolation}"
#=> "OTP: [REDACTED]"

## Direct value() access raises SecurityError (overridden behavior)
single_use_direct_access = SingleUseRedactedString.new(@auth_token)
begin
  single_use_direct_access.value
rescue SecurityError => e
  e.message
end
#=> "Direct value access not allowed for single-use secrets. Use #expose with a block."

## expose method requires block (inherited behavior)
single_use_no_block = SingleUseRedactedString.new(@otp_code)
begin
  single_use_no_block.expose
rescue ArgumentError => e
  e.message
end
#=> "Block required"

## expose method provides access to original value
single_use_expose = SingleUseRedactedString.new("123456")
result = nil
single_use_expose.expose { |val| result = val.dup }
result
#=> "123456"

## expose automatically clears value after use (key single-use behavior)
single_use_auto_clear = SingleUseRedactedString.new(@otp_code)
single_use_auto_clear.expose { |val| val.length }
single_use_auto_clear.cleared?
#=> true

## Second expose attempt raises SecurityError after clearing
single_use_second_expose = SingleUseRedactedString.new(@auth_token)
single_use_second_expose.expose { |val| val.upcase }  # First use
begin
  single_use_second_expose.expose { |val| val }  # Second attempt
rescue SecurityError => e
  e.message
end
#=> "Value already cleared"

## expose clears value even when exception occurs in block
single_use_exception = SingleUseRedactedString.new(@encryption_key)
begin
  single_use_exception.expose { |val| raise "test error" }
rescue => e
  # Exception occurred, but string should still be cleared
end
single_use_exception.cleared?
#=> true

## expose clears value even when block returns early
single_use_early_return = SingleUseRedactedString.new(@otp_code)
result = single_use_early_return.expose do |val|
  next "early" if val.length > 0
  "normal"
end
single_use_early_return.cleared?
#=> true

## Multiple values can be processed in the expose block
single_use_multiple_ops = SingleUseRedactedString.new("password123")
results = []
single_use_multiple_ops.expose do |val|
  results << val.length
  results << val.upcase
  results << val.include?("123")
end
results
#=> [11, "PASSWORD123", true]

## expose with empty string
single_use_empty = SingleUseRedactedString.new(@empty_secret)
result = nil
single_use_empty.expose { |val| result = val.dup }
result
#=> ""

## Can manually expose the length of the value without duplicating
single_use_long = SingleUseRedactedString.new(@long_secret)
result = nil
single_use_long.expose { |val| result = val.length }
result
#=> 50

## Can manually expose the length of the value by duplicating
single_use_long = SingleUseRedactedString.new(@long_secret)
result = nil
single_use_long.expose { |val| result = val.dup.length }
result
#=> 50

## Cannot manually expose the value
single_use_special = SingleUseRedactedString.new(@special_chars)
result = nil
single_use_special.expose { |val| result = val }
result
#=> ""

## Can manually expose the value with special characters by duplicating
single_use_special = SingleUseRedactedString.new(@special_chars)
result = nil
single_use_special.expose { |val| result = val.dup }
result
#=> "tëmp!@#$%"

## Can manually expose the value with special characters by duplicating
single_use_special = SingleUseRedactedString.new(@special_chars)
result = nil
single_use_special.expose { |val| result = val.dup }
result
##=> "tëmp!@#$%"

## expose with special characters via raw method (IN TEST ONLY)
module SpecialTestonlyDirectAccess
  using SingleUseRedactedStringTestHelper
  single_use_special = SingleUseRedactedString.new("tëmp!@#$%")
  # Use raw to access the internal value before expose clears it
  single_use_special.raw
end
#=> "tëmp!@#$%"

## Cleared single-use string maintains redacted appearance
single_use_appearance = SingleUseRedactedString.new(@auth_token)
single_use_appearance.expose { |val| val }  # Use and clear
single_use_appearance.to_s
#=> "[REDACTED]"

## Cleared single-use string inspect still redacted
single_use_inspect_cleared = SingleUseRedactedString.new(@otp_code)
single_use_inspect_cleared.expose { |val| val }  # Use and clear
single_use_inspect_cleared.inspect
#=> "[REDACTED]"

## Object equality works same as parent (inherited behavior)
single_use1 = SingleUseRedactedString.new(@auth_token)
single_use2 = SingleUseRedactedString.new(@auth_token)
single_use1 == single_use2
#=> false

## Same object equality returns true (inherited behavior)
single_use_same = SingleUseRedactedString.new(@otp_code)
single_use_same == single_use_same
#=> true

## eql? behaves same as == (inherited behavior)
single_use_eql1 = SingleUseRedactedString.new(@encryption_key)
single_use_eql2 = SingleUseRedactedString.new(@encryption_key)
single_use_eql1.eql?(single_use_eql2)
#=> false

## Hash behavior consistent with parent (inherited behavior)
single_use_hash1 = SingleUseRedactedString.new(@auth_token)
single_use_hash2 = SingleUseRedactedString.new(@otp_code)
single_use_hash1.hash == single_use_hash2.hash
#=> true

## Hash value consistent with RedactedString class (inherited behavior)
single_use_hash = SingleUseRedactedString.new(@encryption_key)
single_use_hash.hash == RedactedString.hash
#=> true

## Cannot be used in string operations (inherited behavior)
single_use_no_concat = SingleUseRedactedString.new(@auth_token)
begin
  result = single_use_no_concat + "suffix"
  false  # Should not reach here
rescue => e
  true   # Expected to raise error
end
#=> true

## Not a String subclass (inherited behavior)
single_use_type = SingleUseRedactedString.new(@otp_code)
single_use_type.is_a?(String)
#=> false

## Numeric input handling
single_use_numeric = SingleUseRedactedString.new(42)
result = nil
single_use_numeric.expose { |val| result = val.dup }
result
#=> "42"

## Symbol input handling
single_use_symbol = SingleUseRedactedString.new(:secret)
result = nil
single_use_symbol.expose { |val| result = val.dup }
result
#=> "secret"

## Nil input handling
single_use_nil = SingleUseRedactedString.new(nil)
result = nil
single_use_nil.expose { |val| result = val.dup }
result
#=> ""

## Block can return different values
single_use_return_test = SingleUseRedactedString.new("test123")
result = single_use_return_test.expose { |val| "processed: #{val.length}" }
result
#=> "processed: 7"

## clear! method works on SingleUseRedactedString (inherited behavior)
single_use_manual_clear = SingleUseRedactedString.new(@auth_token)
single_use_manual_clear.clear!
single_use_manual_clear.cleared?
#=> true

## Manual clear! prevents subsequent expose
single_use_manual_then_expose = SingleUseRedactedString.new(@otp_code)
single_use_manual_then_expose.clear!
begin
  single_use_manual_then_expose.expose { |val| val }
rescue SecurityError => e
  e.message
end
#=> "Value already cleared"

## freeze behavior after expose (automatic clearing freezes object)
single_use_freeze = SingleUseRedactedString.new(@encryption_key)
single_use_freeze.expose { |val| val }
single_use_freeze.frozen?
#=> true

## Working with sensitive data patterns - OTP example
otp = SingleUseRedactedString.new("123456")
verification_result = otp.expose do |code|
  # Simulate OTP verification
  code == "123456" ? "valid" : "invalid"
end
# OTP is now unusable
[verification_result, otp.cleared?]
#=> ["valid", true]

## Working with sensitive data patterns - temporary token example
temp_token = SingleUseRedactedString.new("temp-xyz-789")
auth_result = temp_token.expose do |token|
  # Simulate authentication
  { success: true, token_length: token.length }
end
# Token is now unusable
[auth_result[:success], temp_token.cleared?]
#=> [true, true]


# TEARDOWN

# Clean up any remaining test objects
@otp_code = nil
@auth_token = nil
@encryption_key = nil
@empty_secret = nil
@long_secret = nil
@special_chars = nil

# Force garbage collection to trigger any finalizers
GC.start
