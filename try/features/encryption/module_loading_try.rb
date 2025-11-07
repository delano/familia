# try/features/encryption/module_loading_try.rb
#
# frozen_string_literal: true

# try/encryption/debug_try.rb

# - Tests that the encryption module loads correctly
# - Validates basic configuration setup

require 'base64'

require_relative '../../support/helpers/test_helpers'

# Test basic functionality

## Check if encryption module loads
defined?(Familia::Encryption)
#=> "constant"

## UnsortedSet and check configuration directly in test
Familia.encryption_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.encryption_keys.is_a?(Hash)
#=> true

## UnsortedSet and check current key version directly in test
Familia.current_key_version = :v1
Familia.current_key_version
#=> :v1


# TEARDOWN
# Clean up
