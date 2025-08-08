# try/features/encryption_fields/missing_current_key_version_try.rb

require 'base64'

require_relative '../../helpers/test_helpers'

# This tryouts file is based on the premise that there is no current key
# version set. This is a global setting so if other tryouts rely on
# having it, they will fail unless they set it for themselves.
Familia.config.current_key_version = nil

class NoCurrentKeyVersionTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :user_id
  field :user_id
  encrypted_field :test_field
end

## Attempt to encrypt will raise an encryption error
model_student = NoCurrentKeyVersionTest.new(user_id: 'derivation-test')
model.test_field = 'test-value'
#=!> Familia::EncryptionError
