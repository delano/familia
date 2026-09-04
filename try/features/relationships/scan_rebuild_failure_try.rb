# try/features/relationships/scan_rebuild_failure_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

# Record fixture for SCAN rebuild failure handling.
class ::ScanRebuildFailureRecord < Familia::Horreum
  feature :relationships

  identifier_field :record_id
  field :record_id
  field :email

  unique_index :email, :email_lookup
end

delete_test_dbkeys(ScanRebuildFailureRecord)

@live_record = ScanRebuildFailureRecord.new(
  record_id: 'live',
  email: 'live@example.test',
)
@live_record.save

# This key matches ScanRebuildFailureRecord.scan_pattern but cannot be loaded
# with HGETALL, forcing the SCAN batch to fail with WRONGTYPE.
@invalid_record_key = ScanRebuildFailureRecord.dbkey('wrong-type')
ScanRebuildFailureRecord.dbclient.set(@invalid_record_key, 'not-a-hash')

@rebuild_result = nil
@rebuild_error = nil

begin
  @rebuild_result = Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_scan(
    ScanRebuildFailureRecord,
    :email,
    :add_to_class_email_lookup,
    ScanRebuildFailureRecord.email_lookup,
    batch_size: 100,
  )
rescue StandardError => e
  @rebuild_error = e
end

## A failed SCAN batch aborts the rebuild
[@rebuild_result, @rebuild_error&.message&.include?('WRONGTYPE')]
#=> [nil, true]

## A failed SCAN batch preserves the live index
ScanRebuildFailureRecord.find_by_email('live@example.test')&.record_id
#=> "live"

delete_test_dbkeys(ScanRebuildFailureRecord)
