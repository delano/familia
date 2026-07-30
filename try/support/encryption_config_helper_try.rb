# try/support/encryption_config_helper_try.rb
#
# frozen_string_literal: true

# Covers try/support/helpers/encryption_config.rb -- the helpers that stop a
# file's encryption config from outliving the file (issue #363).
#
# Every test below installs the config it needs and puts it back, so these
# assertions hold wherever this file sorts in the run. That is the property
# under test, applied to the test itself.

require 'base64'

require_relative 'helpers/test_helpers'

@keyring_a = { v1: Base64.strict_encode64('a' * 32) }
@keyring_b = { v2: Base64.strict_encode64('b' * 32) }

## set_test_encryption_keys installs both halves of the config
set_test_encryption_keys(@keyring_a, current_version: :v1)
@installed = [Familia.config.encryption_keys == @keyring_a,
              Familia.config.current_key_version]
clear_test_encryption_keys
@installed
#=> [true, :v1]

## clear_test_encryption_keys hands the next file an empty keyring
set_test_encryption_keys(@keyring_a, current_version: :v1)
clear_test_encryption_keys
[Familia.config.encryption_keys, Familia.config.current_key_version]
#=> [nil, nil]

## a block override nests inside a file-scoped one, restoring it on exit
set_test_encryption_keys(@keyring_a, current_version: :v1)
@inside = with_test_encryption_keys(@keyring_b, current_version: :v2) do
  [Familia.config.encryption_keys == @keyring_b, Familia.config.current_key_version]
end
@outside = [Familia.config.encryption_keys == @keyring_a,
            Familia.config.current_key_version]
clear_test_encryption_keys
[@inside, @outside]
#=> [[true, :v2], [true, :v1]]

## a block that raises still restores what it displaced
set_test_encryption_keys(@keyring_a, current_version: :v1)
@raised = begin
  with_test_encryption_keys(@keyring_b, current_version: :v2) { raise ArgumentError, 'boom' }
rescue ArgumentError
  :raised
end
@after_raise = [Familia.config.encryption_keys == @keyring_a,
                Familia.config.current_key_version]
clear_test_encryption_keys
[@raised, @after_raise]
#=> [:raised, [true, :v1]]

## only the first install records the baseline, so widening a keyring is safe
set_test_encryption_keys(@keyring_a, current_version: :v1)
set_test_encryption_keys(@keyring_a.merge(@keyring_b), current_version: :v2)
clear_test_encryption_keys
[Familia.config.encryption_keys, Familia.config.current_key_version]
#=> [nil, nil]

## clear with no matching install falls back to an empty keyring
# This is the shape of a file that only sets the config inline, inside its test
# cases: there is no baseline to restore, and clearing outright is correct.
Familia.config.encryption_keys = @keyring_a
Familia.config.current_key_version = :v1
clear_test_encryption_keys
[Familia.config.encryption_keys, Familia.config.current_key_version]
#=> [nil, nil]

## installing over an unscoped config warns, naming the file that is installing
# The config is populated but no helper put it there, which is what an earlier
# file forgetting its teardown looks like from here.
Familia.config.encryption_keys = @keyring_a
Familia.config.current_key_version = :v1
set_test_encryption_keys(@keyring_b, current_version: :v2)
clear_test_encryption_keys # hands back the unscoped config it warned about...
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil # ...so drop that too
#=2> /already installed on entry/
#=2> /encryption_config_helper_try\.rb/

## a previous file that forgot its teardown is caught, not inherited
# The baseline belongs to the file that recorded it. Another file's outstanding
# install must not make this file's install skip the leak check, and must not
# become what this file restores to -- otherwise a forgotten teardown is silent
# and the leak is handed to the file after this one.
TestEncryptionConfig.install(@keyring_a, :v1, '/somewhere/else_try.rb')
set_test_encryption_keys(@keyring_b, current_version: :v2)
clear_test_encryption_keys
[Familia.config.encryption_keys, Familia.config.current_key_version]
#=> [nil, nil]
#=2> /already installed on entry/
#=2> /encryption_config_helper_try\.rb/

## installing a keyring wipes the fiber-local derived-key cache
# The cache is keyed by version and context, not by the master key the entry was
# derived from, so an entry that outlived a keyring swap would be served under
# the new keyring.
Fiber[:familia_request_cache_enabled] = true
Fiber[:familia_request_cache] = { 'aes-256-gcm:v1::ctx' => +'derived-under-keyring-a' }
set_test_encryption_keys(@keyring_a, current_version: :v1)
# Both fiber-locals go back to their pristine nil, not to the `false` that
# Familia::Encryption.clear_request_cache! leaves behind -- request_cache_try
# asserts an untouched fiber reads nil.
@cache_after_install = [Fiber[:familia_request_cache], Fiber[:familia_request_cache_enabled]]
clear_test_encryption_keys
@cache_after_install
#=> [nil, nil]

# TEARDOWN
clear_test_encryption_keys
