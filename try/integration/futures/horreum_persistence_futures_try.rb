# try/integration/futures/horreum_persistence_futures_try.rb
#
# frozen_string_literal: true

# Horreum write and refresh paths inside transaction and pipelined blocks.
# These methods need command replies (unique-index guards, their own EXEC
# result, fields read back), so inside a block they raise
# Familia::OperationModeError before changing anything. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# These fixture classes belong to one scenario, so they share this file.
# rubocop:disable Style/OneClassPerFile
# Record with a class-level unique index, whose guard reads an index hash.
class FuturesSaveRecord < Familia::Horreum
  feature :relationships
  identifier_field :recid
  field :recid
  field :email
  field :name
  unique_index :email, :email_lookup
end

# Record without indexes, for the partial writers.
class FuturesPartialRecord < Familia::Horreum
  identifier_field :recid
  field :recid
  field :name
  field :nickname
end
# rubocop:enable Style/OneClassPerFile

delete_test_dbkeys(FuturesSaveRecord, FuturesPartialRecord)

@saved = FuturesSaveRecord.new(recid: 'fsr-1', email: 'one@example.com', name: 'one')
@saved.save
@partial = FuturesPartialRecord.new(recid: 'fpr-1', name: 'original', nickname: 'orig')
@partial.save

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## save inside a pipeline raises OperationModeError, not a spurious RecordExistsError
@fresh = FuturesSaveRecord.new(recid: 'fsr-2', email: 'two@example.com', name: 'two')
[@refused.call { FuturesSaveRecord.pipelined { @fresh.save } }, FuturesSaveRecord.exists?('fsr-2')]
#=> [Familia::OperationModeError, false]

## save of an existing record inside a pipeline raises OperationModeError too
@saved.name = 'renamed'
[@refused.call { FuturesSaveRecord.pipelined { @saved.save } }, FuturesSaveRecord.load('fsr-1').name]
#=> [Familia::OperationModeError, "one"]

## save inside a transaction keeps its message
@err = nil
begin
  FuturesSaveRecord.transaction { @fresh.save }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.include?('Cannot call save within a transaction')
#=> true

## save_if_not_exists!, create! and build inside a pipeline raise OperationModeError
[
  @refused.call { FuturesSaveRecord.pipelined { @fresh.save_if_not_exists! } },
  @refused.call { FuturesSaveRecord.pipelined { FuturesSaveRecord.create!(recid: 'fsr-3', email: 'e3@example.com') } },
  @refused.call { FuturesSaveRecord.pipelined { FuturesSaveRecord.build(recid: 'fsr-4', email: 'four@example.com') } },
  FuturesSaveRecord.email_lookup.values_at('two@example.com', 'e3@example.com', 'four@example.com'),
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, []]

## atomic_write inside a pipeline raises OperationModeError
@refused.call { FuturesSaveRecord.pipelined { @fresh.atomic_write { @fresh.name = 'x' } } }
#=> Familia::OperationModeError

## Familia.atomic_write inside a pipeline raises OperationModeError in every form
# Plain, unique-indexed, and the create-only watch_keys/pre_check form,
# whose pre_check would see a truthy Future from exists?.
@plain = FuturesPartialRecord.new(recid: 'fpr-aw', name: 'plain')
@indexed = FuturesSaveRecord.new(recid: 'fsr-aw', email: 'aw@example.com', name: 'aw')
@create_only = lambda do
  Familia.atomic_write(@plain, watch_keys: [@plain.dbkey],
                               pre_check: -> { raise Familia::RecordExistsError, @plain.dbkey if @plain.exists? }) do
    @plain.name = 'created'
  end
end
[
  @refused.call { Familia.pipelined { Familia.atomic_write(@plain) { @plain.name = 'x' } } },
  @refused.call { Familia.pipelined { Familia.atomic_write(@indexed) { @indexed.name = 'x' } } },
  @refused.call { Familia.pipelined { @create_only.call } },
  FuturesPartialRecord.exists?('fpr-aw'),
  FuturesSaveRecord.exists?('fsr-aw'),
]
#=> [Familia::OperationModeError, Familia::OperationModeError, Familia::OperationModeError, false, false]

## Familia.atomic_write inside a pipeline names itself in the error
@err = nil
begin
  Familia.pipelined { Familia.atomic_write(@indexed) { @indexed.name = 'x' } }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.start_with?('Cannot call Familia.atomic_write within a transaction or pipeline')
#=> true

## Familia.atomic_write inside a transaction raises OperationModeError
@refused.call { Familia.transaction { Familia.atomic_write(@plain) { @plain.name = 'x' } } }
#=> Familia::OperationModeError

## outside a block: Familia.atomic_write persists both records, and create-only then refuses
[Familia.atomic_write(@plain, @indexed) { @plain.name = 'together' }, FuturesPartialRecord.load('fpr-aw').name,
 FuturesSaveRecord.find_by_email('aw@example.com').recid, @refused.call { @create_only.call }]
#=> [true, "together", "fsr-aw", Familia::RecordExistsError]

## the generated unique-index guard inside a pipeline raises OperationModeError
@refused.call { FuturesSaveRecord.pipelined { @fresh.guard_unique_email_lookup! } }
#=> Familia::OperationModeError

## commit_fields inside a transaction raises and queues nothing
@partial.name = 'txn-commit'
[@refused.call { @partial.transaction { @partial.commit_fields } }, FuturesPartialRecord.load('fpr-1').name,
 @partial.dirty?(:name)]
#=> [Familia::OperationModeError, "original", true]

## save_fields inside a pipeline raises and queues nothing
@partial.name = 'pipe-save-fields'
[@refused.call { @partial.pipelined { @partial.save_fields(:name) } }, FuturesPartialRecord.load('fpr-1').name]
#=> [Familia::OperationModeError, "original"]

## multi_field_update inside a transaction raises before touching in-memory state
@partial.refresh!
[@refused.call { @partial.transaction { @partial.multi_field_update(nickname: 'txn') } },
 @partial.nickname, @partial.dirty?(:nickname), FuturesPartialRecord.load('fpr-1').nickname]
#=> [Familia::OperationModeError, "orig", false, "orig"]

## multi_field_fast_write inside a pipeline raises before touching in-memory state
[@refused.call { @partial.pipelined { @partial.multi_field_fast_write(nickname: 'pipe') } },
 @partial.nickname, FuturesPartialRecord.load('fpr-1').nickname]
#=> [Familia::OperationModeError, "orig", "orig"]

## refresh! and refresh inside a transaction raise OperationModeError
[@refused.call { @partial.transaction { @partial.refresh! } },
 @refused.call { @partial.pipelined { @partial.refresh } }]
#=> [Familia::OperationModeError, Familia::OperationModeError]

## single-field fast writers still queue inside a transaction
@ret = nil
@partial.transaction { @ret = @partial.nickname!('fast') }
[@ret.class, FuturesPartialRecord.load('fpr-1').nickname]
#=> [Redis::Future, "fast"]

## outside a block: the partial writers and refresh still work
@partial.name = 'outside'
@partial.commit_fields
@partial.multi_field_update(nickname: 'mfu')
@partial.multi_field_fast_write(name: 'mffw')
@partial.nickname = 'sf'
@partial.save_fields(:nickname)
@loaded = FuturesPartialRecord.load('fpr-1')
[@loaded.name, @loaded.nickname, @partial.refresh.nickname, @partial.dirty?]
#=> ["mffw", "sf", "sf", false]

## outside a block: save and create! still claim unique values
@fresh.save
[FuturesSaveRecord.find_by_email('two@example.com').recid,
 FuturesSaveRecord.create!(recid: 'fsr-5', email: 'five@example.com').recid]
#=> ["fsr-2", "fsr-5"]

# Teardown
delete_test_dbkeys(FuturesSaveRecord, FuturesPartialRecord)
