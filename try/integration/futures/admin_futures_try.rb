# try/integration/futures/admin_futures_try.rb
#
# frozen_string_literal: true

# Horreum audit, repair and key-scan entry points inside transaction and
# pipelined blocks. They scan keys and compare replies, so inside a block
# they raise Familia::OperationModeError before issuing anything. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Indexed record, so every audit and repair stage has something to inspect.
class FuturesAdminRecord < Familia::Horreum
  feature :relationships
  identifier_field :recid
  field :recid
  field :email
  field :dept
  unique_index :email, :email_lookup
  multi_index :dept, :dept_index
end

delete_test_dbkeys(FuturesAdminRecord)

FuturesAdminRecord.new(recid: 'far-1', email: 'a1@example.com', dept: 'ops').save

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## audits and the key scan inside a pipeline raise OperationModeError
[
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.audit_instances } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.audit_unique_indexes } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.audit_multi_indexes } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.audit_participations } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.audit_related_fields } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.audit_cross_references } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.health_check } },
  @refused.call { FuturesAdminRecord.pipelined { FuturesAdminRecord.scan_keys { |_key| nil } } },
].uniq
#=> [Familia::OperationModeError]

## repairs inside a transaction raise OperationModeError
[
  @refused.call { FuturesAdminRecord.transaction { FuturesAdminRecord.repair_instances! } },
  @refused.call { FuturesAdminRecord.transaction { FuturesAdminRecord.repair_indexes! } },
  @refused.call { FuturesAdminRecord.transaction { FuturesAdminRecord.repair_multi_indexes! } },
  @refused.call { FuturesAdminRecord.transaction { FuturesAdminRecord.repair_participations! } },
  @refused.call { FuturesAdminRecord.transaction { FuturesAdminRecord.repair_related_fields! } },
  @refused.call { FuturesAdminRecord.transaction { FuturesAdminRecord.repair_all! } },
].uniq
#=> [Familia::OperationModeError]

## the error names the refused entry point
@err = nil
begin
  FuturesAdminRecord.pipelined { FuturesAdminRecord.health_check }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.include?('FuturesAdminRecord.health_check cannot run inside a transaction or pipeline')
#=> true

## scan_keys without a block still returns an Enumerator inside a pipeline
@enum = nil
FuturesAdminRecord.pipelined { @enum = FuturesAdminRecord.scan_keys }
@enum.class
#=> Enumerator

## outside a block: audits, repairs and the key scan still run
[FuturesAdminRecord.audit_instances[:phantoms], FuturesAdminRecord.health_check.healthy?,
 FuturesAdminRecord.repair_instances!.class, FuturesAdminRecord.scan_keys.to_a]
#=> [[], true, Hash, ["futures_admin_record:far-1:object"]]

# Teardown
delete_test_dbkeys(FuturesAdminRecord)
