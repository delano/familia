# try/audit/audit_cross_references_try.rb
#
# frozen_string_literal: true

# audit_cross_references: detects drift between the instances ZSET and
# class-level unique indexes. Covers the empty-index case, healthy baseline,
# forward drift (missing index entry), split-brain (wrong identifier),
# nil/empty fields skipped, multiple unique indexes, scoped-index skip, and
# health_check opt-in wiring.

require_relative '../support/helpers/test_helpers'

class ACRPlainModel < Familia::Horreum
  identifier_field :pid
  field :pid
  field :name
end

class ACRIndexedUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :name

  unique_index :email, :email_index
end

class ACRMultiUniqueIndex < Familia::Horreum
  feature :relationships

  identifier_field :uid
  field :uid
  field :email
  field :username
  field :name

  unique_index :email, :email_index
  unique_index :username, :username_index
end

class ACRScopedParent < Familia::Horreum
  feature :relationships

  identifier_field :pid
  field :pid
  field :name
end

class ACRScopedChild < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid
  field :email
  field :badge
  field :name

  unique_index :email, :email_index
  unique_index :badge, :badge_index, within: ACRScopedParent
end

def acr_reset(klass)
  existing = Familia.dbclient.keys("#{klass.prefix}:*")
  Familia.dbclient.del(*existing) if existing.any?
rescue StandardError
  # ignore cleanup errors
ensure
  klass.instances.clear if klass.respond_to?(:instances)
end

## audit_cross_references exists as a class method
ACRIndexedUser.respond_to?(:audit_cross_references)
#=> true

## Class with no unique indexes returns empty result with status :ok
acr_reset(ACRPlainModel)
@plain = ACRPlainModel.new(pid: 'p-1', name: 'Plain')
@plain.save
@result = ACRPlainModel.audit_cross_references
@result[:status]
#=> :ok

## Class with no unique indexes: in_instances_missing_unique_index is empty
acr_reset(ACRPlainModel)
@plain = ACRPlainModel.new(pid: 'p-1', name: 'Plain')
@plain.save
ACRPlainModel.audit_cross_references[:in_instances_missing_unique_index]
#=> []

## Class with no unique indexes: index_points_to_wrong_identifier is empty
acr_reset(ACRPlainModel)
@plain = ACRPlainModel.new(pid: 'p-1', name: 'Plain')
@plain.save
ACRPlainModel.audit_cross_references[:index_points_to_wrong_identifier]
#=> []

## Healthy baseline returns status :ok
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-2', email: 'bob@example.com', name: 'Bob')
@u2.save
@u3 = ACRIndexedUser.new(user_id: 'cr-3', email: 'carol@example.com', name: 'Carol')
@u3.save
ACRIndexedUser.audit_cross_references[:status]
#=> :ok

## Healthy baseline: in_instances_missing_unique_index is empty
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-2', email: 'bob@example.com', name: 'Bob')
@u2.save
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index]
#=> []

## Healthy baseline: index_points_to_wrong_identifier is empty
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-1', email: 'alice@example.com', name: 'Alice')
@u1.save
ACRIndexedUser.audit_cross_references[:index_points_to_wrong_identifier]
#=> []

## Missing index entry (forward drift): flagged in in_instances_missing_unique_index
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-miss', email: 'missing@example.com', name: 'Missing')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'missing@example.com')
@result = ACRIndexedUser.audit_cross_references
@result[:in_instances_missing_unique_index].size
#=> 1

## Missing index entry: record carries the expected identifier
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-miss', email: 'missing@example.com', name: 'Missing')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'missing@example.com')
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index].first[:identifier]
#=> 'cr-miss'

## Missing index entry: record carries the expected field_value
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-miss', email: 'missing@example.com', name: 'Missing')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'missing@example.com')
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index].first[:field_value]
#=> 'missing@example.com'

## Missing index entry: record carries the index_name
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-miss', email: 'missing@example.com', name: 'Missing')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'missing@example.com')
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index].first[:index_name]
#=> :email_index

## Missing index entry: existing_index_value is nil
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-miss', email: 'missing@example.com', name: 'Missing')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'missing@example.com')
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index].first[:existing_index_value]
#=> nil

## Missing index entry: overall status is :issues_found
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-miss', email: 'missing@example.com', name: 'Missing')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'missing@example.com')
ACRIndexedUser.audit_cross_references[:status]
#=> :issues_found

## Wrong identifier (split-brain): flagged in index_points_to_wrong_identifier
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-sb-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-sb-2', email: 'bob@example.com', name: 'Bob')
@u2.save
Familia.dbclient.hset(ACRIndexedUser.email_index.dbkey, 'alice@example.com', '"cr-sb-2"')
@result = ACRIndexedUser.audit_cross_references
@result[:index_points_to_wrong_identifier].any? { |r| r[:expected_id] == 'cr-sb-1' }
#=> true

## Wrong identifier: expected_id and index_id are distinct
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-sb-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-sb-2', email: 'bob@example.com', name: 'Bob')
@u2.save
Familia.dbclient.hset(ACRIndexedUser.email_index.dbkey, 'alice@example.com', '"cr-sb-2"')
@entry = ACRIndexedUser.audit_cross_references[:index_points_to_wrong_identifier].find { |r| r[:expected_id] == 'cr-sb-1' }
[@entry[:expected_id], @entry[:index_id]]
#=> ['cr-sb-1', 'cr-sb-2']

## Wrong identifier: entry carries the field_value
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-sb-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-sb-2', email: 'bob@example.com', name: 'Bob')
@u2.save
Familia.dbclient.hset(ACRIndexedUser.email_index.dbkey, 'alice@example.com', '"cr-sb-2"')
@entry = ACRIndexedUser.audit_cross_references[:index_points_to_wrong_identifier].find { |r| r[:expected_id] == 'cr-sb-1' }
@entry[:field_value]
#=> 'alice@example.com'

## Wrong identifier: entry carries the index_name
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-sb-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-sb-2', email: 'bob@example.com', name: 'Bob')
@u2.save
Familia.dbclient.hset(ACRIndexedUser.email_index.dbkey, 'alice@example.com', '"cr-sb-2"')
@entry = ACRIndexedUser.audit_cross_references[:index_points_to_wrong_identifier].find { |r| r[:expected_id] == 'cr-sb-1' }
@entry[:index_name]
#=> :email_index

## Wrong identifier: status is :issues_found
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-sb-1', email: 'alice@example.com', name: 'Alice')
@u1.save
@u2 = ACRIndexedUser.new(user_id: 'cr-sb-2', email: 'bob@example.com', name: 'Bob')
@u2.save
Familia.dbclient.hset(ACRIndexedUser.email_index.dbkey, 'alice@example.com', '"cr-sb-2"')
ACRIndexedUser.audit_cross_references[:status]
#=> :issues_found

## Nil field value: instance is skipped (not flagged as missing)
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
# Persist directly via commit_fields to avoid index auto-population on save
@u1 = ACRIndexedUser.new(user_id: 'cr-nil', email: nil, name: 'NoEmail')
Familia.dbclient.hset(@u1.dbkey, 'user_id', '"cr-nil"')
Familia.dbclient.hset(@u1.dbkey, 'name', '"NoEmail"')
ACRIndexedUser.instances.add('cr-nil', Familia.now)
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index]
#=> []

## Empty-string field value: instance is skipped
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-empty', email: '', name: 'Empty')
Familia.dbclient.hset(@u1.dbkey, 'user_id', '"cr-empty"')
Familia.dbclient.hset(@u1.dbkey, 'email', '""')
Familia.dbclient.hset(@u1.dbkey, 'name', '"Empty"')
ACRIndexedUser.instances.add('cr-empty', Familia.now)
ACRIndexedUser.audit_cross_references[:in_instances_missing_unique_index]
#=> []

## Multiple unique indexes: both are audited independently
acr_reset(ACRMultiUniqueIndex)
ACRMultiUniqueIndex.email_index.clear
ACRMultiUniqueIndex.username_index.clear
@m = ACRMultiUniqueIndex.new(uid: 'mu-1', email: 'multi@example.com', username: 'multiuser', name: 'Multi')
@m.save
# Delete only the email index entry; username_index should remain healthy
Familia.dbclient.hdel(ACRMultiUniqueIndex.email_index.dbkey, 'multi@example.com')
@result = ACRMultiUniqueIndex.audit_cross_references
@result[:in_instances_missing_unique_index].map { |r| r[:index_name] }
#=> [:email_index]

## Multiple unique indexes: healthy index is not flagged
acr_reset(ACRMultiUniqueIndex)
ACRMultiUniqueIndex.email_index.clear
ACRMultiUniqueIndex.username_index.clear
@m = ACRMultiUniqueIndex.new(uid: 'mu-1', email: 'multi@example.com', username: 'multiuser', name: 'Multi')
@m.save
Familia.dbclient.hdel(ACRMultiUniqueIndex.email_index.dbkey, 'multi@example.com')
ACRMultiUniqueIndex.audit_cross_references[:in_instances_missing_unique_index].none? { |r| r[:index_name] == :username_index }
#=> true

## Instance-scoped unique indexes are not audited (only class-level)
acr_reset(ACRScopedChild)
ACRScopedChild.email_index.clear
@c = ACRScopedChild.new(cid: 'sc-1', email: 'child@example.com', badge: 'B-100', name: 'Child')
@c.save
# Even though badge_index within: ACRScopedParent is not populated, the audit
# should ignore it and only check the class-level email_index.
ACRScopedChild.audit_cross_references[:status]
#=> :ok

## Instance-scoped unique indexes: no entries reference badge_index
acr_reset(ACRScopedChild)
ACRScopedChild.email_index.clear
@c = ACRScopedChild.new(cid: 'sc-1', email: 'child@example.com', badge: 'B-100', name: 'Child')
@c.save
@result = ACRScopedChild.audit_cross_references
(@result[:in_instances_missing_unique_index] + @result[:index_points_to_wrong_identifier]).none? { |r| r[:index_name] == :badge_index }
#=> true

## health_check default does NOT call audit_cross_references
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-default', email: 'hc@example.com', name: 'HC')
@u1.save
ACRIndexedUser.health_check.cross_references
#=> nil

## health_check default: complete? is false because cross_references was skipped
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-default', email: 'hc@example.com', name: 'HC')
@u1.save
ACRIndexedUser.health_check.complete?
#=> false

## health_check with check_cross_refs: true populates cross_references
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-on', email: 'hc-on@example.com', name: 'On')
@u1.save
@report = ACRIndexedUser.health_check(check_cross_refs: true)
@report.cross_references.is_a?(Hash)
#=> true

## health_check with check_cross_refs: true carries status :ok on clean state
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-on', email: 'hc-on@example.com', name: 'On')
@u1.save
ACRIndexedUser.health_check(check_cross_refs: true).cross_references[:status]
#=> :ok

## health_check with check_cross_refs: true surfaces drift as unhealthy
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-drift', email: 'drift@example.com', name: 'Drift')
@u1.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'drift@example.com')
ACRIndexedUser.health_check(check_cross_refs: true).healthy?
#=> false

## AuditReport.to_h includes cross_references as nil when not checked
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
ACRIndexedUser.health_check.to_h[:cross_references]
#=> nil

## AuditReport.to_h cross_references summary contains the three keys when checked
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-h', email: 'h@example.com', name: 'H')
@u1.save
@h = ACRIndexedUser.health_check(check_cross_refs: true).to_h[:cross_references]
@h.keys.sort
#=> [:in_instances_missing_unique_index, :index_points_to_wrong_identifier, :status]

## AuditReport.to_s mentions cross_references not_checked when skipped
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
ACRIndexedUser.health_check.to_s.include?('cross_references: not_checked')
#=> true

## AuditReport.to_s includes cross_references summary line when checked
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'hc-s', email: 's@example.com', name: 'S')
@u1.save
ACRIndexedUser.health_check(check_cross_refs: true).to_s.include?('cross_references: missing_index_entries=')
#=> true

## AuditReport healthy? returns true when cross_references is nil (not checked)
@nil_cr_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 0, count_scan: 0 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  related_fields: [],
  cross_references: nil,
  duration: 0.1
)
@nil_cr_report.healthy?
#=> true

## AuditReport healthy? returns false when cross_references has drift
@drift_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 0, count_scan: 0 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  related_fields: [],
  cross_references: {
    in_instances_missing_unique_index: [{ identifier: 'x', index_name: :foo, field_value: 'y', existing_index_value: nil }],
    index_points_to_wrong_identifier: [],
    status: :issues_found,
  },
  duration: 0.1
)
@drift_report.healthy?
#=> false

## AuditReport complete? requires cross_references to be non-nil
@incomplete_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 0, count_scan: 0 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  related_fields: [],
  cross_references: nil,
  duration: 0.1
)
@incomplete_report.complete?
#=> false

## AuditReport complete? true when both related_fields and cross_references non-nil
@complete_report = Familia::Horreum::AuditReport.new(
  model_class: 'TestModel',
  audited_at: Familia.now,
  instances: { phantoms: [], missing: [], count_timeline: 0, count_scan: 0 },
  unique_indexes: [],
  multi_indexes: [],
  participations: [],
  related_fields: [],
  cross_references: { in_instances_missing_unique_index: [], index_points_to_wrong_identifier: [], status: :ok },
  duration: 0.1
)
@complete_report.complete?
#=> true

## Phantom in instances ZSET (no hash key) is ignored by cross_references audit
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'cr-live', email: 'live@example.com', name: 'Live')
@u1.save
ACRIndexedUser.instances.add('ghost-id', Familia.now)
@phantom_result = ACRIndexedUser.audit_cross_references
[@phantom_result[:in_instances_missing_unique_index],
 @phantom_result[:index_points_to_wrong_identifier]]
#=> [[], []]

## Combined drift: missing index entry AND wrong identifier surface together
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u_miss = ACRIndexedUser.new(user_id: 'cb-miss', email: 'miss@example.com', name: 'Miss')
@u_miss.save
@u_wrong = ACRIndexedUser.new(user_id: 'cb-wrong', email: 'wrong@example.com', name: 'Wrong')
@u_wrong.save
Familia.dbclient.hdel(ACRIndexedUser.email_index.dbkey, 'miss@example.com')
Familia.dbclient.hset(ACRIndexedUser.email_index.dbkey, 'wrong@example.com', '"other-id"')
@combined = ACRIndexedUser.audit_cross_references
[@combined[:in_instances_missing_unique_index].any? { |r| r[:identifier] == 'cb-miss' },
 @combined[:index_points_to_wrong_identifier].any? { |r| r[:expected_id] == 'cb-wrong' && r[:index_id] == 'other-id' },
 @combined[:status]]
#=> [true, true, :issues_found]

## Progress callback yields phase: :cross_references with current/total keys
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@u1 = ACRIndexedUser.new(user_id: 'pc-1', email: 'pc1@example.com', name: 'PC1')
@u1.save
@progress_calls = []
ACRIndexedUser.audit_cross_references do |info|
  @progress_calls << info
end
@progress_calls.any? { |p| p[:phase] == :cross_references && p.key?(:current) && p.key?(:total) }
#=> true

## Non-default batch_size produces identical result to default
acr_reset(ACRIndexedUser)
ACRIndexedUser.email_index.clear
@s1 = ACRIndexedUser.new(user_id: 'bs-1', email: 'bs1@example.com', name: 'One')
@s1.save
@s2 = ACRIndexedUser.new(user_id: 'bs-2', email: 'bs2@example.com', name: 'Two')
@s2.save
@s3 = ACRIndexedUser.new(user_id: 'bs-3', email: 'bs3@example.com', name: 'Three')
@s3.save
@s4 = ACRIndexedUser.new(user_id: 'bs-4', email: 'bs4@example.com', name: 'Four')
@s4.save
@s5 = ACRIndexedUser.new(user_id: 'bs-5', email: 'bs5@example.com', name: 'Five')
@s5.save
@default_result = ACRIndexedUser.audit_cross_references
@batched_result = ACRIndexedUser.audit_cross_references(batch_size: 2)
@default_result == @batched_result
#=> true

# Teardown
acr_reset(ACRPlainModel)
acr_reset(ACRIndexedUser)
acr_reset(ACRMultiUniqueIndex)
acr_reset(ACRScopedParent)
acr_reset(ACRScopedChild)
