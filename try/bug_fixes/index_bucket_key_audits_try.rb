# try/bug_fixes/index_bucket_key_audits_try.rb
#
# frozen_string_literal: true

# audit_related_fields and audit_participations SCAN for
# "<prefix>:*:<name>" and read the part the wildcard matched as a record
# identifier. The name of a multi_index bucket ends with a field value, so
# a field value equal to <name> put the bucket in that pattern:
#
# - "bk_user:role_index:notes" (class-level role_index, role "notes")
#   parsed as the notes list of a missing record "role_index", and
#   repair_related_fields! deleted it.
# - "bk_co:c-1:dept_index:tags" (dept_index within BkCo, dept "tags")
#   parsed as the tags set of a missing record "c-1:dept_index", and
#   repair_related_fields! deleted it.
# - "bk_co:industry_index:staff" parsed as the staff collection of a
#   target "industry_index", and repair_participations! removed every
#   member, because no participant has a company's identifier. With a
#   sorted set collection, audit_participations raised WRONGTYPE.
#
# Both audits now pass SCAN's TYPE option for the type the field or
# collection stores and leave out keys that
# RecordKeyOwnership.index_bucket_owner reads as a bucket.
#
# The instance-scoped multi_index audit matches
# "<scope prefix>:*:<index>:*", so a class-level bucket of the scope class
# whose value contains ":dept_index:" was reported as an orphaned bucket
# of a missing scope. It now leaves such a key out unless that scope
# record exists.

require_relative '../support/helpers/test_helpers'

# Class-level multi_index next to a list and a set related field.
class ::BkUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  list :notes
  set :tags
  multi_index :role, :role_index
end

# Scope and participation target class, with its own class-level index.
class ::BkCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
  field :industry
  set :tags
  multi_index :industry, :industry_index
end

# Instance-scoped multi_index within BkCo and a set participation.
class ::BkEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::BkCo
  participates_in ::BkCo, :staff, type: :set
end

# Sorted set participation whose name a company industry can equal.
class ::BkCrew < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  participates_in ::BkCo, :crew
end

# Second index within BkCo whose members are not BkEmp identifiers.
class ::BkVendor < Familia::Horreum
  feature :relationships
  identifier_field :vid
  field :vid
  field :kind
  multi_index :kind, :vendor_index, within: ::BkCo
  participates_in ::BkCo, :vendors
end

@ownership = Familia::Features::Relationships::Indexing::RecordKeyOwnership
delete_test_dbkeys(BkUser, BkCo, BkEmp, BkCrew, BkVendor)

## Class-level bucket named like a list field: the audit does not report it
@u1 = BkUser.new(uid: 'u1', role: 'notes')
@u1.save
BkUser.rebuild_role_index
@notes_bucket = BkUser.role_index_for('notes').dbkey
[@notes_bucket, BkUser.audit_related_fields.map { |r| [r[:field_name], r[:orphaned_keys]] }]
#=> ["bk_user:role_index:notes", [[:notes, []], [:tags, []]]]

## Class-level bucket named like a set field: the audit does not report it
@u2 = BkUser.new(uid: 'u2', role: 'tags')
@u2.save
BkUser.rebuild_role_index
@tags_bucket = BkUser.role_index_for('tags').dbkey
[@tags_bucket, BkUser.audit_related_fields.map { |r| [r[:field_name], r[:orphaned_keys]] }]
#=> ["bk_user:role_index:tags", [[:notes, []], [:tags, []]]]

## repair_related_fields! removes real orphans and keeps both class-level buckets
@gone = BkUser.new(uid: 'gone')
@gone.save
@gone.notes.push('n')
@gone.tags.add('t')
Familia.dbclient.del(@gone.dbkey)
@result = BkUser.repair_related_fields!
[
  @result[:removed_keys].sort,
  Familia.dbclient.smembers(@notes_bucket),
  Familia.dbclient.smembers(@tags_bucket),
]
#=> [["bk_user:gone:notes", "bk_user:gone:tags"], ["u1"], ["u2"]]

## repair_all! with collections leaves the class-level index intact
BkUser.repair_all!(audit_collections: true)
[BkUser.find_all_by_role('notes').map(&:uid), BkUser.find_all_by_role('tags').map(&:uid)]
#=> [["u1"], ["u2"]]

## Instance-scoped bucket named like a set field of the scope: repair keeps it
@c1 = BkCo.new(cid: 'c-1')
@c1.save
@e1 = BkEmp.new(eid: 'e1', dept: 'tags')
@e1.save
@e1.add_to_bk_co_staff(@c1)
@c1.rebuild_dept_index
@scope_bucket = @c1.dept_index_for('tags').dbkey
@result = BkCo.repair_related_fields!
[@scope_bucket, @result[:removed_keys], Familia.dbclient.smembers(@scope_bucket)]
#=> ["bk_co:c-1:dept_index:tags", [], ["e1"]]

## A scope identifier holding glob characters and the delimiter keeps its bucket
@c2 = BkCo.new(cid: 'c-*:x')
@c2.save
@e2 = BkEmp.new(eid: 'e2', dept: 'tags')
@e2.save
@e2.add_to_bk_co_staff(@c2)
@c2.rebuild_dept_index
@glob_bucket = @c2.dept_index_for('tags').dbkey
@result = BkCo.repair_related_fields!
[@glob_bucket, @result[:removed_keys], Familia.dbclient.smembers(@glob_bucket)]
#=> ["bk_co:c-*:x:dept_index:tags", [], ["e2"]]

## The bucket of a scope whose hash is gone is still reported as an orphan
@c3 = BkCo.new(cid: 'c-3')
@c3.save
@e3 = BkEmp.new(eid: 'e3', dept: 'tags')
@e3.save
@e3.add_to_bk_co_staff(@c3)
@c3.rebuild_dept_index
@orphan_bucket = @c3.dept_index_for('tags').dbkey
Familia.dbclient.del(@c3.dbkey)
@result = BkCo.repair_related_fields!
[@result[:removed_keys].include?(@orphan_bucket), Familia.dbclient.smembers(@scope_bucket)]
#=> [true, ["e1"]]

## Set participation: a class-level bucket of the target is not a collection
@c4 = BkCo.new(cid: 'c-4', industry: 'staff')
@c4.save
BkCo.rebuild_industry_index
@industry_bucket = BkCo.industry_index_for('staff').dbkey
[@industry_bucket, BkEmp.audit_participations.flat_map { |r| r[:stale_members] }]
#=> ["bk_co:industry_index:staff", []]

## repair_participations! leaves the members of that bucket alone
BkEmp.repair_participations!
Familia.dbclient.smembers(@industry_bucket)
#=> ["c-4"]

## Sorted set participation: a set bucket of the same name no longer raises WRONGTYPE
@c5 = BkCo.new(cid: 'c-5', industry: 'crew')
@c5.save
BkCo.rebuild_industry_index
[BkCrew.audit_participations.flat_map { |r| r[:stale_members] }, BkCo.find_all_by_industry('crew').map(&:cid)]
#=> [[], ["c-5"]]

## Set participation: an instance-scoped bucket of another index keeps its members
@v1 = BkVendor.new(vid: 'v1', kind: 'staff')
@v1.save
@v1.add_to_bk_co_vendors(@c1)
@c1.rebuild_vendor_index
@vendor_bucket = @c1.vendor_index_for('staff').dbkey
BkEmp.repair_participations!
[@vendor_bucket, Familia.dbclient.smembers(@vendor_bucket)]
#=> ["bk_co:c-1:vendor_index:staff", ["v1"]]

## A real stale member of a real staff collection is still removed
Familia.dbclient.sadd(@c1.staff.dbkey, 'ghost-emp')
BkEmp.repair_participations!
@c1.staff.membersraw.sort
#=> ["e1"]

## index_bucket_owner: a class-level bucket belongs to the class
@ownership.index_bucket_owner('bk_user:role_index:notes', BkUser)
#=> BkUser

## index_bucket_owner: an instance-scoped bucket belongs to its existing scope
@ownership.index_bucket_owner('bk_co:c-1:dept_index:tags', BkCo)
#=> 'c-1'

## index_bucket_owner: glob characters and the delimiter in the scope identifier
@ownership.index_bucket_owner('bk_co:c-*:x:dept_index:tags', BkCo)
#=> 'c-*:x'

## index_bucket_owner: the longest existing scope identifier wins
@d1 = BkCo.new(cid: 'd-1')
@d1.save
@d2 = BkCo.new(cid: 'd-1:dept_index:x')
@d2.save
@ownership.index_bucket_owner('bk_co:d-1:dept_index:x:dept_index:ops', BkCo)
#=> 'd-1:dept_index:x'

## index_bucket_owner: no bucket when no scope record exists
@ownership.index_bucket_owner('bk_co:nope:dept_index:tags', BkCo)
#=> nil

## index_bucket_owner: a record's own field key is not a bucket
@ownership.index_bucket_owner('bk_co:c-1:tags', BkCo)
#=> nil

## index_bucket_owner: a key outside the class prefix is not a bucket
@ownership.index_bucket_owner('bk_user:role_index:notes', BkCo)
#=> nil

## index_bucket_owner: a glob character does not stand for the index name
@ownership.index_bucket_owner('bk_user:role_inde?:notes', BkUser)
#=> nil

## class_level_bucket?: matches only the class-level index prefix of the class
[
  @ownership.class_level_bucket?('bk_co:industry_index:staff', BkCo),
  @ownership.class_level_bucket?('bk_co:c-1:dept_index:tags', BkCo),
  @ownership.class_level_bucket?('bk_co:industry_index:staff', BkUser),
]
#=> [true, false, false]

## audit_multi_indexes does not read a class-level bucket as another index's bucket
@c6 = BkCo.new(cid: 'c-6', industry: 'x:dept_index:ops')
@c6.save
BkCo.rebuild_industry_index
@cross_bucket = BkCo.industry_index_for('x:dept_index:ops').dbkey
@dept_audit = BkEmp.audit_multi_indexes.find { |r| r[:index_name] == :dept_index }
[@cross_bucket, @dept_audit[:orphaned_keys]]
#=> ["bk_co:industry_index:x:dept_index:ops", []]

## repair_all! keeps that class-level bucket
BkEmp.repair_all!
BkCo.find_all_by_industry('x:dept_index:ops').map(&:cid)
#=> ["c-6"]

delete_test_dbkeys(BkUser, BkCo, BkEmp, BkCrew, BkVendor)
