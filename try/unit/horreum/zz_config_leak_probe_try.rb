# try/unit/horreum/zz_config_leak_probe_try.rb
#
# frozen_string_literal: true
#
# TEMPORARY probe: asserts no prior tryout file leaked global encryption config.

require_relative '../../support/helpers/test_helpers'

## encryption_keys is not carrying a previous file's override
Familia.config.encryption_keys
#=> nil

## current_key_version is not carrying a previous file's override
Familia.config.current_key_version
#=> nil
