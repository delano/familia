# try/features/encryption/instance_variable_scope_try.rb
#
# frozen_string_literal: true

# try/encryption/debug3_try.rb

# - Tests instance variable scoping in tryouts framework
# - Validates that variables persist within test sections


require 'base64'

require_relative '../../support/helpers/test_helpers'

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
# Block form: the override is scoped to this test case, so nothing is left
# installed for the next file in the shared-context run (issue #363).
with_test_encryption_keys(@test_keys, current_version: :v1) do
  Familia::Encryption.encrypt('test', context: 'test').nil?
end
#=> false


# TEARDOWN
