# try/encryption/debug2_try.rb

# - Tests configuration persistence between test sections
# - Validates that config can be set and accessed in tryouts

require 'base64'

require_relative '../helpers/test_helpers'
require 'familia/encryption/providers/xchacha20_poly1305_provider'

# SETUP
Familia.config.encryption_keys = {
  v1: Base64.strict_encode64('a' * 32)
}
Familia.config.current_key_version = :v1

## Check config in test
keys = Familia.config.encryption_keys
version = Familia.config.current_key_version
[keys.nil?, version.nil?]
#=> [false, false]

## Try basic encryption in test
Familia.config.encryption_keys = {v1: Base64.strict_encode64('a' * 32)}
Familia.config.current_key_version = :v1
result = Familia::Encryption.encrypt('test', context: 'test')
result.nil?
#=> false


# TEARDOWN
