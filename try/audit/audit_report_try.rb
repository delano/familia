# try/audit/audit_report_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

## AuditReport is defined
defined?(Familia::Horreum::AuditReport)
#=> "constant"

## AuditReport responds to .new with keyword args
@healthy_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 5, count_scan: 5 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  duration: 0.123
)
@healthy_report.class.name
#=> "Familia::Horreum::AuditReport"

## healthy? returns true when all dimensions are clean
@healthy_report.healthy?
#=> true

## healthy? returns false when phantoms exist
@phantom_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: ['ghost-1'], missing: [], count_timeline: 6, count_scan: 5 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  duration: 0.1
)
@phantom_report.healthy?
#=> false

## healthy? returns false when missing entries exist
@missing_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: ['obj-1'], count_timeline: 4, count_scan: 5 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  duration: 0.1
)
@missing_report.healthy?
#=> false

## healthy? returns false with stale unique index entries
@stale_idx_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 5, count_scan: 5 },
  unique_indexes: [{ index_name: :email_lookup, stale: [{ field_value: 'old@test.com' }], missing: [] }],
  multi_indexes: [],
  participations: [],
  duration: 0.1
)
@stale_idx_report.healthy?
#=> false

## healthy? returns false with stale participation members
@stale_part_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 5, count_scan: 5 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [{ collection_name: :members, stale_members: [{ identifier: 'gone' }] }],
  duration: 0.1
)
@stale_part_report.healthy?
#=> false

## to_h returns a hash with summary counts
h = @phantom_report.to_h
h[:healthy]
#=> false

## to_h instances shows phantom count
@phantom_report.to_h[:instances][:phantoms]
#=> 1

## to_h instances shows count_timeline
@phantom_report.to_h[:instances][:count_timeline]
#=> 6

## to_s returns a string containing model class name
@healthy_report.to_s.include?('TestModel')
#=> true

## to_s contains HEALTHY for clean report
@healthy_report.to_s.include?('HEALTHY')
#=> true

## to_s contains UNHEALTHY for dirty report
@phantom_report.to_s.include?('UNHEALTHY')
#=> true

## to_s includes duration
@healthy_report.to_s.include?('0.123')
#=> true
