# frozen_string_literal: true

# Regression coverage for the unique-index SCAN rebuild fallback.
#
# Exercises the strategy directly because every Horreum currently exposes an
# instances timeline, so class-level generated rebuild methods prefer that path.

require_relative '../../support/helpers/test_helpers'

# Minimal indexed model used to exercise the direct SCAN strategy.
class ScanRebuildRecord < Familia::Horreum
  feature :relationships

  identifier_field :record_id
  field :record_id
  field :email

  unique_index :email, :email_lookup

  def self.rebuild_via_scan_for_test(batch_size: 2, &progress)
    Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_scan(
      self,
      :email,
      :add_to_class_email_lookup,
      email_lookup,
      batch_size: batch_size,
      &progress
    )
  end
end

delete_test_dbkeys(ScanRebuildRecord)

@alpha = ScanRebuildRecord.new(record_id: 'scan-alpha', email: 'alpha@example.com')
@alpha.save
@beta = ScanRebuildRecord.new(record_id: 'scan-beta', email: 'beta@example.com')
@beta.save
@gamma = ScanRebuildRecord.new(record_id: 'scan-gamma', email: 'gamma@example.com')
@gamma.save
@blank = ScanRebuildRecord.new(record_id: 'scan-blank', email: nil)
@blank.save

@expected_index = {
  'alpha@example.com' => 'scan-alpha',
  'beta@example.com' => 'scan-beta',
  'gamma@example.com' => 'scan-gamma',
}

## SCAN rebuild replaces stale data with the exact live index contents
ScanRebuildRecord.email_lookup.clear
ScanRebuildRecord.email_lookup['stale@example.com'] = 'missing-record'
@rebuilt_count = ScanRebuildRecord.rebuild_via_scan_for_test(batch_size: 2)
[@rebuilt_count, ScanRebuildRecord.email_lookup.all]
#=> [3, {"alpha@example.com"=>"scan-alpha", "beta@example.com"=>"scan-beta", "gamma@example.com"=>"scan-gamma"}]

## SCAN rebuild reports progress while processing multiple batches
@progress = []
ScanRebuildRecord.rebuild_via_scan_for_test(batch_size: 2) { |update| @progress << update }
@progress.length >= 2 && @progress.all? { |update| update[:completed] <= update[:scanned] }
#=> true

## A failed SCAN batch raises and leaves the live index unchanged
@live_index = ScanRebuildRecord.email_lookup.all
@invalid_record_key = ScanRebuildRecord.dbkey('wrong-type')
ScanRebuildRecord.dbclient.set(@invalid_record_key, 'not-a-hash')
@raised = begin
  ScanRebuildRecord.rebuild_via_scan_for_test(batch_size: 100)
  false
rescue StandardError
  true
ensure
  ScanRebuildRecord.dbclient.del(@invalid_record_key)
end
[@raised, ScanRebuildRecord.email_lookup.all == @live_index]
#=> [true, true]

## Redis command errors returned by a batch transaction are propagated
@command_error = Redis::CommandError.new('simulated batch command failure')
@propagated_error = begin
  Familia::Features::Relationships::Indexing::RebuildStrategies.ensure_scan_batch_succeeded!(
    Familia::MultiResult.new([@command_error]),
  )
  nil
rescue Redis::CommandError => e
  e
end
@propagated_error.equal?(@command_error)
#=> true

## An aborted batch transaction raises instead of allowing the index swap
begin
  Familia::Features::Relationships::Indexing::RebuildStrategies.ensure_scan_batch_succeeded!(
    Familia::MultiResult.new(nil),
  )
  false
rescue Familia::Problem => e
  e.message == 'SCAN rebuild batch transaction aborted'
end
#=> true

# Teardown
delete_test_dbkeys(ScanRebuildRecord)
