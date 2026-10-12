# try/bug_fixes/multi_index_record_ownership_try.rb
#
# frozen_string_literal: true

# The multi_index rebuild and audits decide whether a key under a bucket
# prefix belongs to another record (see RecordKeyOwnership). They took a
# record as existing when its hash key existed. With a field value equal
# to the class suffix, the bucket "ro_user:role_index:object" sits at the
# hash key of a record "role_index", which does not exist. So:
#
# - a second value equal to a set field name made the rebuild raise
#   Familia::IndexBucketConflictError, naming that bucket as the owner;
# - a stale bucket of such a value was left in place by the rebuild while
#   the audit and health_check reported the index as healthy;
# - repair_participations! removed the members of a bucket whose value
#   equaled a set collection name.
#
# A record now exists only when its hash key holds a hash. The candidate
# owners of a key are checked in one pipeline, and a key with more of them
# than RecordKeyOwnership::MAX_CANDIDATE_SPLITS is not checked: the rebuild
# raises for it before it deletes anything, and the audit reports it.
# repair_multi_indexes! records a rebuild that raises the conflict error
# and goes on with the next scope or index.

require_relative '../support/helpers/test_helpers'

# Class-level multi_indexes on a class with a set field.
class ::RoUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  field :tier
  set :tags
  multi_index :role, :role_index
  multi_index :tier, :tier_index
end

# Scope class with a set field and a class-level multi_index.
class ::RoCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
  field :industry
  set :tags
  multi_index :industry, :industry_index
end

# Instance-scoped multi_index within RoCo.
class ::RoEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::RoCo
  participates_in ::RoCo, :staff
end

# Set participation whose name a company industry or a dept can equal.
class ::RoCrew < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  participates_in ::RoCo, :crew, type: :set
end

@ownership = Familia::Features::Relationships::Indexing::RecordKeyOwnership
@client = Familia.dbclient
@delete_keys = lambda do
  delete_test_dbkeys(RoUser, RoCo, RoEmp, RoCrew)
end
@delete_keys.call

## Class-level: the bucket of value "object" is a set, and no record is named after the index
@u1 = RoUser.new(uid: 'u1', role: 'object')
@u1.save
@u2 = RoUser.new(uid: 'u2', role: 'tags')
@u2.save
RoUser.rebuild_role_index
[
  @client.type('ro_user:role_index:object'),
  @ownership.existing_records(RoUser, %w[role_index u1]),
  @ownership.other_record_key_owner('ro_user:role_index:tags', RoUser),
]
#=> ["set", [false, true], nil]

## Class-level: the rebuild writes the bucket of a value equal to a set field name
[RoUser.rebuild_role_index, RoUser.role_index_for('tags').members, RoUser.role_index_for('object').members]
#=> [2, ["u2"], ["u1"]]

## Class-level: the audit reports a stale member of that bucket
@client.sadd('ro_user:role_index:tags', '"ghost"')
@audit = RoUser.audit_multi_indexes.find { |result| result[:index_name] == :role_index }
[@audit[:status], @audit[:stale_members].map { |entry| entry[:indexed_id] }, RoUser.health_check.healthy?]
#=> [:issues_found, ["ghost"], false]

## Class-level: the rebuild clears that stale member
RoUser.rebuild_role_index
[RoUser.role_index_for('tags').members, RoUser.audit_multi_indexes.map { |result| result[:status] }, RoUser.health_check.healthy?]
#=> [["u2"], [:ok, :ok], true]

## Class-level: a stale bucket of a value equal to a set field name is cleared
@u2.role = 'admin'
@u2.save
RoUser.rebuild_role_index
[RoUser.role_index_for('tags').exists?, RoUser.role_index_for('admin').members]
#=> [false, ["u2"]]

## Instance-scoped: the scope's own "object" bucket is not taken for a record
@c1 = RoCo.new(cid: 'c-1', industry: 'object')
@c1.save
@e1 = RoEmp.new(eid: 'e1', dept: 'object')
@e1.save
@e1.add_to_ro_co_staff(@c1)
@e2 = RoEmp.new(eid: 'e2', dept: 'tags')
@e2.save
@e2.add_to_ro_co_staff(@c1)
[@c1.rebuild_dept_index, @c1.rebuild_dept_index, @c1.dept_index_for('tags').members, @c1.dept_index_for('object').members]
#=> [2, 2, ["e2"], ["e1"]]

## Instance-scoped: the audit reports a stale member of that bucket, and the rebuild clears it
@c1.dept_index_for('tags').add('e-ghost')
@before = RoEmp.audit_multi_indexes.first
@c1.rebuild_dept_index
[
  @before[:status],
  @before[:stale_members].map { |entry| entry[:indexed_id] },
  @c1.dept_index_for('tags').members,
  RoEmp.audit_multi_indexes.first[:status],
]
#=> [:issues_found, ["e-ghost"], ["e2"], :ok]

## A value repeating the delimiter and an index name stops the rebuild within a few round trips
@c5 = RoCo.new(cid: 'c-5')
@c5.save
@long_value = 'x:dept_index:' * 2000
@e6 = RoEmp.new(eid: 'e6', dept: @long_value)
@e6.save
@e6.add_to_ro_co_staff(@c5)
@c5.dept_index_for('old').add('e-old')
@long_key = "ro_co:c-5:dept_index:#{@long_value}"
@commands = DatabaseLogger.capture_commands do
  @c5.rebuild_dept_index
rescue Familia::IndexBucketConflictError => e
  @long_conflict = e
end
[@long_conflict&.conflicts, @commands.size < 5, @c5.dept_index_for('old').members]
#=> [{ @long_key => :too_many_candidate_owners }, true, ["e-old"]]

## The error message says the owner of that key was not checked
@long_conflict.message.include?('(owner not checked: too_many_candidate_owners)')
#=> true

## The audit reports such a bucket without an owner, and health_check counts it
@e6.add_to_ro_co_dept_index(@c5)
@commands = DatabaseLogger.capture_commands { @long_audit = RoEmp.audit_multi_indexes.first }
[
  @long_audit[:status],
  @long_audit[:foreign_owned_keys].map { |entry| entry.values_at(:key, :owner_key, :reason, :scope_id) },
  @commands.count { |entry| entry.command.include?(@long_value) },
  RoEmp.health_check.healthy?,
]
#=> [:issues_found, [[@long_key, nil, :too_many_candidate_owners, "c-5"]], 0, false]

## The rebuild also stops before deleting when such a bucket is stale
@e6.dept = 'ops'
@e6.save
begin
  @c5.rebuild_dept_index
rescue Familia::IndexBucketConflictError => e
  @stale_conflict = e
end
[@stale_conflict&.conflicts, @client.exists(@long_key), @c5.dept_index_for('old').members]
#=> [{ @long_key => :too_many_candidate_owners }, 1, ["e-old"]]

## A set field of another record is reported as foreign-owned and does not count against health
@client.del(@long_key)
@c5.dept_index_for('old').clear
@c5.rebuild_dept_index
@c9 = RoCo.new(cid: 'c-9')
@c9.save
@c9_owner = RoCo.new(cid: 'c-9:dept_index')
@c9_owner.save
@c9_owner.tags.add('keep')
@owned = RoEmp.audit_multi_indexes.first
[
  @owned[:status],
  @owned[:foreign_owned_keys].map { |entry| entry.values_at(:key, :owner_key, :reason, :scope_id) },
]
#=> [:ok, [["ro_co:c-9:dept_index:tags", "ro_co:c-9:dept_index:object", :other_record, "c-9"]]]

## A class-level set field of a record named after the index is reported the same way
@u1.role = 'admin'
@u1.save
RoUser.rebuild_role_index
@role_owner = RoUser.new(uid: 'role_index', role: 'member')
@role_owner.save
@role_owner.tags.add('keep')
RoUser.rebuild_role_index
@class_owned = RoUser.audit_multi_indexes.find { |result| result[:index_name] == :role_index }
[@class_owned[:status], @class_owned[:foreign_owned_keys].map { |entry| entry.values_at(:key, :owner_key, :reason) }]
#=> [:ok, [["ro_user:role_index:tags", "ro_user:role_index:object", :other_record]]]

## Set participation: buckets named like the collection are not audited as collections
@c2 = RoCo.new(cid: 'c-2', industry: 'crew')
@c2.save
RoCo.rebuild_industry_index
@e3 = RoEmp.new(eid: 'e3', dept: 'crew')
@e3.save
@e3.add_to_ro_co_staff(@c1)
@c1.rebuild_dept_index
@m1 = RoCrew.new(mid: 'm1')
@m1.save
@m1.add_to_ro_co_crew(@c1)
[
  @client.type('ro_co:industry_index:crew'),
  @client.type('ro_co:c-1:dept_index:crew'),
  RoCrew.audit_participations.flat_map { |result| result[:stale_members] },
]
#=> ["set", "set", []]

## Set participation: repair_participations! leaves both buckets intact
[
  RoCrew.repair_participations!,
  RoCo.find_all_by_industry('crew').map(&:cid),
  @c1.find_all_by_dept('crew').map(&:eid),
  @c1.crew.members,
]
#=> [{ stale_removed: 0 }, ["c-2"], ["e3"], ["m1"]]

## Set participation: the indexes still rebuild afterwards
[RoCo.rebuild_industry_index, @c1.rebuild_dept_index, RoCo.find_all_by_industry('crew').map(&:cid)]
#=> [5, 3, ["c-2"]]

## Set participation: a stale member of a real collection is still reported and removed
@m_ghost = RoCrew.new(mid: 'm-ghost')
@m_ghost.save
@m_ghost.add_to_ro_co_crew(@c1)
@client.del(@m_ghost.dbkey)
@stale = RoCrew.audit_participations.flat_map { |result| result[:stale_members] }
[@stale.map { |entry| entry[:collection_key] }, RoCrew.repair_participations!, @c1.crew.members]
#=> [["ro_co:c-1:crew"], { stale_removed: 1 }, ["m1"]]

## repair_multi_indexes! records a conflicting scope and repairs the scopes after it
@c3 = RoCo.new(cid: 'c-3')
@c3.save
@e4 = RoEmp.new(eid: 'e4', dept: 'sales')
@e4.save
@e4.add_to_ro_co_staff(@c3)
@client.set('ro_co:c-3:dept_index:sales', 'not a bucket')
@c4 = RoCo.new(cid: 'c-4')
@c4.save
@e5 = RoEmp.new(eid: 'e5', dept: 'eng')
@e5.save
@e5.add_to_ro_co_staff(@c4)
@repaired = RoEmp.repair_multi_indexes!
[
  @repaired[:rebuilt_per_scope],
  @repaired[:skipped].map { |entry| entry.values_at(:index_name, :scope_id, :reason, :conflicts) },
  @c4.dept_index_for('eng').members,
  @client.get('ro_co:c-3:dept_index:sales'),
]
#=> [[{ index_name: :dept_index, scopes_rebuilt: 6 }], [[:dept_index, "c-3", :bucket_conflict, { "ro_co:c-3:dept_index:sales" => "string" }]], ["e5"], "not a bucket"]

## repair_all! reports the conflict with status :partial_failure
@c4.dept_index_for('eng').clear
@result = RoEmp.repair_all!
[
  @result[:status],
  @result[:errors],
  @result[:multi_indexes][:skipped].map { |entry| entry.values_at(:scope_id, :reason) },
  @c4.dept_index_for('eng').members,
]
#=> [:partial_failure, {}, [["c-3", :bucket_conflict]], ["e5"]]

## repair_multi_indexes! records a conflicting class-level index and rebuilds the next one
@client.del('ro_co:c-3:dept_index:sales')
@c3.rebuild_dept_index
@u3 = RoUser.new(uid: 'u3', role: 'notes', tier: 'gold')
@u3.save
@client.del('ro_user:role_index:notes')
@client.set('ro_user:role_index:notes', 'not a bucket')
@client.sadd('ro_user:tier_index:gold', '"tier-ghost"')
@class_repaired = RoUser.repair_multi_indexes!
[
  @class_repaired[:rebuilt],
  @class_repaired[:skipped].map { |entry| entry.values_at(:index_name, :reason, :conflicts) },
  RoUser.tier_index_for('gold').members,
]
#=> [[:tier_index], [[:role_index, :bucket_conflict, { "ro_user:role_index:notes" => "string" }]], ["u3"]]

@delete_keys.call
