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

## Configured keys read back through the Familia.* spelling of the setting
# Familia.encryption_keys and Familia.config.encryption_keys are the same
# setting -- Familia.config returns Familia itself -- so this spelling leaks
# across files exactly like the other one (issue #363).
set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) }, current_version: :v1)
Familia.encryption_keys.is_a?(Hash)
#=> true

## The current key version reads back through that spelling too
Familia.current_key_version
#=> :v1


# TEARDOWN
clear_test_encryption_keys
