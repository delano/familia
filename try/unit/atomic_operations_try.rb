# try/unit/atomic_operations_try.rb
#
# frozen_string_literal: true

# Direct unit tests for Familia::AtomicOperations.
#
# Covers the two public primitives that back index rebuilds and audit/repair
# routines:
#   - build_temp_key: timestamped temp key name with the :rebuild: marker
#   - atomic_swap:    RENAME when temp key exists, DEL otherwise; idempotent
#                     when final_key is absent
#
# Concurrent race detection lives in try/features/relationships/indexing_rebuild_try.rb;
# this file guards against accidental behavioral changes to the module methods
# themselves during future refactors.

require_relative '../support/helpers/test_helpers'

def ao_reset(*keys)
  Familia.dbclient.del(*keys) if keys.any?
end

## build_temp_key includes the base key prefix
@temp = Familia::AtomicOperations.build_temp_key('myindex:live')
@temp.start_with?('myindex:live:')
#=> true

## build_temp_key includes the :rebuild: marker
Familia::AtomicOperations.build_temp_key('myindex:live').include?(':rebuild:')
#=> true

## build_temp_key includes a numeric timestamp suffix
@temp = Familia::AtomicOperations.build_temp_key('x:y')
@suffix = @temp.split(':rebuild:').last
@suffix.match?(/\A\d+\z/)
#=> true

## build_temp_key returns a String
Familia::AtomicOperations.build_temp_key('base').is_a?(String)
#=> true

## atomic_swap with populated temp key RENAMEs onto final_key
ao_reset('ao_swap:final', 'ao_swap:temp')
Familia.dbclient.hset('ao_swap:temp', 'field', 'value')
Familia::AtomicOperations.atomic_swap('ao_swap:temp', 'ao_swap:final', Familia.dbclient)
[Familia.dbclient.exists('ao_swap:temp'),
 Familia.dbclient.hget('ao_swap:final', 'field')]
#=> [0, "value"]

## atomic_swap with populated temp key replaces an existing final_key
ao_reset('ao_swap2:final', 'ao_swap2:temp')
Familia.dbclient.hset('ao_swap2:final', 'field', 'old')
Familia.dbclient.hset('ao_swap2:temp', 'field', 'new')
Familia::AtomicOperations.atomic_swap('ao_swap2:temp', 'ao_swap2:final', Familia.dbclient)
Familia.dbclient.hget('ao_swap2:final', 'field')
#=> "new"

## atomic_swap with empty result set DELs the final key
ao_reset('ao_swap3:final', 'ao_swap3:temp')
Familia.dbclient.hset('ao_swap3:final', 'stale', 'value')
Familia::AtomicOperations.atomic_swap('ao_swap3:temp', 'ao_swap3:final', Familia.dbclient)
Familia.dbclient.exists('ao_swap3:final')
#=> 0

## atomic_swap is idempotent when neither temp nor final exists
ao_reset('ao_swap4:final', 'ao_swap4:temp')
Familia::AtomicOperations.atomic_swap('ao_swap4:temp', 'ao_swap4:final', Familia.dbclient)
Familia.dbclient.exists('ao_swap4:final')
#=> 0

# Teardown
ao_reset(
  'ao_swap:final', 'ao_swap:temp',
  'ao_swap2:final', 'ao_swap2:temp',
  'ao_swap3:final', 'ao_swap3:temp',
  'ao_swap4:final', 'ao_swap4:temp',
)
