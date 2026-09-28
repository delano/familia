# try/integration/futures/features_futures_try.rb
#
# frozen_string_literal: true

# Identifier finders and housekeeping chores inside transaction and
# pipelined blocks. They read a lookup or scan instances before they can
# answer, so inside a block they raise Familia::OperationModeError. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Record with both identifier lookups and a capped list chore.
class FuturesFeatureRecord < Familia::Horreum
  feature :object_identifier
  feature :external_identifier
  feature :housekeeping
  identifier_field :recid
  field :recid
  list :log, max_length: 2
  chore :caps, Familia::Features::Housekeeping::EnforceCollectionCaps
end

delete_test_dbkeys(FuturesFeatureRecord)

@rec = FuturesFeatureRecord.new(recid: 'ffr-1')
@rec.save

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## find_by_objid and find_by_extid inside a transaction raise OperationModeError
[
  @refused.call { FuturesFeatureRecord.transaction { FuturesFeatureRecord.find_by_objid(@rec.objid) } },
  @refused.call { FuturesFeatureRecord.transaction { FuturesFeatureRecord.find_by_extid(@rec.extid) } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError]

## find_by_objid and find_by_extid inside a pipeline raise OperationModeError
[
  @refused.call { FuturesFeatureRecord.pipelined { FuturesFeatureRecord.find_by_objid(@rec.objid) } },
  @refused.call { FuturesFeatureRecord.pipelined { FuturesFeatureRecord.find_by_extid(@rec.extid) } },
]
#=> [Familia::OperationModeError, Familia::OperationModeError]

## run_chores! inside a pipeline raises OperationModeError
@refused.call { FuturesFeatureRecord.pipelined { FuturesFeatureRecord.run_chores! } }
#=> Familia::OperationModeError

## the collection-cap chore inside a transaction raises and trims nothing
@rec.log.delete!
Familia.dbclient.rpush(@rec.log.dbkey, %w[1 2 3 4])
[@refused.call { @rec.transaction { @rec.do_chore!(:caps) } }, @rec.log.size]
#=> [Familia::OperationModeError, 4]

## outside a block: the identifier finders still load the record
[FuturesFeatureRecord.find_by_objid(@rec.objid).recid, FuturesFeatureRecord.find_by_extid(@rec.extid).recid]
#=> ["ffr-1", "ffr-1"]

## outside a block: the chore trims and reports the removed count
[@rec.do_chore!(:caps), @rec.log.size, FuturesFeatureRecord.run_chores![:scanned]]
#=> [2, 2, 1]

# Teardown
delete_test_dbkeys(FuturesFeatureRecord)
