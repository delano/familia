# try/bug_fixes/multi_index_tail_index_name_ownership_try.rb
#
# frozen_string_literal: true

# With companies "c-1" and "c-1:dept_index:x", the bucket of dept
# "x:dept_index" in c-1 is "ti_co:c-1:dept_index:x:dept_index". That key
# also reads as "<scope key>:dept_index" of the longer company, the key the
# factories name for a blank value. No multi_index method reads or writes
# that key, so it is not the longer company's index data.
# RecordKeyOwnership still counted an index name that ends a key as a
# candidate owner split, so it gave the bucket to the longer company:
# rebuilding c-1 raised Familia::IndexBucketConflictError, the audit listed
# the bucket as foreign-owned, health_check stayed false, and a stale
# bucket of that value was never cleared. An index name now makes a
# candidate split only when the delimiter follows it.

require_relative '../support/helpers/test_helpers'

class ::TiCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
end

class ::TiEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::TiCo
  participates_in ::TiCo, :staff
end

@client = Familia.dbclient
delete_test_dbkeys(TiCo, TiEmp)

@short = TiCo.new(cid: 'c-1')
@short.save
@long = TiCo.new(cid: 'c-1:dept_index:x')
@long.save
@emp = TiEmp.new(eid: 'e1', dept: 'x:dept_index')
@emp.save
@emp.add_to_ti_co_staff(@short)
@emp.add_to_ti_co_dept_index(@short)
@bucket = @short.dept_index_for('x:dept_index').dbkey

## The bucket of c-1 ends in the index name
[@bucket, @short.find_all_by_dept('x:dept_index').map(&:eid)]
#=> ["ti_co:c-1:dept_index:x:dept_index", ["e1"]]

## The longer company is not a candidate owner of that bucket
Familia::Features::Relationships::Indexing::RecordKeyOwnership.other_record_key_owner(@bucket, @short)
#=> nil

## Rebuilding c-1 writes the bucket instead of raising
[@short.rebuild_dept_index, @client.smembers(@bucket)]
#=> [1, ["e1"]]

## The audit reads the bucket for c-1, and health_check is healthy
@audit = TiEmp.audit_multi_indexes.first
[@audit.values_at(:status, :missing, :stale_members, :orphaned_keys, :foreign_owned_keys), TiEmp.health_check.healthy?]
#=> [[:ok, [], [], [], []], true]

## Rebuilding the longer company leaves the bucket of c-1 in place
[@long.rebuild_dept_index, @client.smembers(@bucket)]
#=> [0, ["e1"]]

## A stale bucket of that value is reported for c-1
# save refreshes the index add-only, so e1 stays in the old bucket.
@emp.dept = 'ops'
@emp.save
@stale = TiEmp.audit_multi_indexes.first
[@stale[:status], @stale[:foreign_owned_keys], @short.find_all_by_dept('x:dept_index').map(&:eid)]
#=> [:issues_found, [], ["e1"]]

## Rebuilding c-1 clears the stale bucket
[@short.rebuild_dept_index, @client.exists(@bucket), @short.find_all_by_dept('x:dept_index').map(&:eid), @short.find_all_by_dept('ops').map(&:eid)]
#=> [1, 0, [], ["e1"]]

## repair_multi_indexes! clears it too and skips nothing
@client.sadd(@bucket, 'e1')
@repair = TiEmp.repair_multi_indexes!
[@repair[:skipped], @client.exists(@bucket), TiEmp.audit_multi_indexes.first[:status], TiEmp.health_check.healthy?]
#=> [[], 0, :ok, true]

# Teardown
delete_test_dbkeys(TiCo, TiEmp)
