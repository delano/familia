# try/unit/core/suite_hygiene_try.rb
#
# frozen_string_literal: true

# Suite hygiene guard (issue #283): no tryout file may call FLUSHDB or
# FLUSHALL. The whole suite shares one Valkey/Redis server (logical db 0
# unless a model overrides it), so a flush in one file erases another
# file's live data mid-run -- the suite is order-fragile sequentially and
# unsafe under --parallel. Use the scoped cleanup helper instead:
# `delete_test_dbkeys` in try/support/helpers/test_helpers.rb.
#
# The forbidden-word regex is case-sensitive and this file spells the
# commands in uppercase only, so the guard does not match itself. There
# is no allowlist on purpose: the expected offender count is zero.

require_relative '../../support/helpers/test_helpers'

## No *_try.rb file under try/ contains a lowercase FLUSHDB/FLUSHALL call
try_root = File.expand_path('../..', __dir__)
forbidden = /\bflush(?:db|all)\b/
offenders = Dir.glob(File.join(try_root, '**', '*_try.rb')).select do |path|
  File.read(path).match?(forbidden)
end
offenders.map { |path| path.sub("#{try_root}/", '') }.sort
#=> []
