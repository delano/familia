# try/features/encrypted_fields/memory_security_try.rb
#
# frozen_string_literal: true

# try/features/encryption_fields/memory_security_try.rb

require 'base64'
require_relative '../../support/helpers/test_helpers'

test_keys = {
  v1: Base64.strict_encode64('a' * 32),
}
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

## Keys are wiped from memory after use
# Note: This is difficult to test directly, but we can verify
# the secure_wipe method is called

class WipeTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :id
  field :id
  encrypted_field :secret
end

# Monkey-patch to track wipe calls
wipe_calls = 0
original_wipe = Familia::Encryption.singleton_method(:secure_wipe)
Familia::Encryption.define_singleton_method(:secure_wipe) do |key|
  wipe_calls += 1
  original_wipe.call(key)
end

model = WipeTest.new(id: 'wipe-1')
model.secret = 'test'
model.secret

# Should wipe master key after each derivation (2 operations = 2 wipes)
wipe_calls >= 2
#=> true
