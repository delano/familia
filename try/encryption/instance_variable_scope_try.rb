# try/encryption/debug3_try.rb

# - Tests instance variable scoping in tryouts framework
# - Validates that variables persist within test sections


require 'base64'

require_relative '../helpers/test_helpers'

@test_keys = {
  v1: Base64.strict_encode64('a' * 32)
}

## Check if instance variables work
@test_keys.nil?
#=> false

## Check if we can access specific key
@test_keys[:v1].nil?
#=> false

## UnsortedSet config and check immediately in same test
Familia.config.encryption_keys = @test_keys
Familia.config.current_key_version = :v1
result = Familia::Encryption.encrypt('test', context: 'test')
result.nil?
#=> false


# TEARDOWN
