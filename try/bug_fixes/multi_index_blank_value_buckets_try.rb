# try/bug_fixes/multi_index_blank_value_buckets_try.rb
#
# frozen_string_literal: true

# A multi_index does not index a blank field value (nil, empty or
# whitespace only), whether it is class-level or instance-scoped.
#
# The factories name the bucket of a blank value "<owner key>:<index>",
# without the trailing delimiter of every other bucket. The instance-scoped
# add_to_* used to write blank values there, but the rebuild SCANs only
# "<owner key>:<index>:*" and the audit only "<scope>:*:<index>:*", so a
# stale member of that bucket was never cleared or reported. Now add_to_*
# and update_in_* skip blank values, the rebuild deletes the blank-value
# bucket with the other buckets, and audit_multi_indexes reports it as an
# orphaned bucket with field value "".

require_relative '../support/helpers/test_helpers'

class ::BvCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
end

class ::BvEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::BvCo
  participates_in ::BvCo, :staff
end

class ::BvUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  multi_index :role, :role_index
end

@client = Familia.dbclient
delete_test_dbkeys(BvCo, BvEmp, BvUser)

@co = BvCo.new(cid: 'c-1')
@co.save
@blank = BvEmp.new(eid: 'e1', dept: '')
@blank.save
@blank.add_to_bv_co_staff(@co)
@spaces = BvEmp.new(eid: 'e2', dept: '  ')
@spaces.save
@spaces.add_to_bv_co_staff(@co)
@ops = BvEmp.new(eid: 'e3', dept: 'ops')
@ops.save
@ops.add_to_bv_co_staff(@co)
@ops.add_to_bv_co_dept_index(@co)

## The bucket of a blank value has no trailing delimiter
[@co.dept_index_for('').dbkey, @co.dept_index_for('  ').dbkey, BvUser.role_index_for('').dbkey]
#=> ["bv_co:c-1:dept_index", "bv_co:c-1:dept_index", "bv_user:role_index"]

## Instance-scoped add_to_* does not index empty and whitespace-only values, as the class-level index does
@blank.add_to_bv_co_dept_index(@co)
@spaces.add_to_bv_co_dept_index(@co)
[
  @client.exists('bv_co:c-1:dept_index'),
  @co.find_all_by_dept('').map(&:eid),
  @co.find_all_by_dept('ops').map(&:eid),
]
#=> [0, [], ["e3"]]

## add_to_* still tracks the membership of a blank value
[@blank.send(:_index_scope_tracker).hgetall, @spaces.send(:_index_scope_tracker).hgetall]
#=> [{ "bv_co\tdept_index\tc-1\t" => '' }, { "bv_co\tdept_index\tc-1\t  " => '  ' }]

## So save indexes the object once its value is no longer blank
@spaces.dept = 'sales'
@spaces.save
[@co.find_all_by_dept('sales').map(&:eid), @client.exists('bv_co:c-1:dept_index')]
#=> [["e2"], 0]

## update_in_* to a blank value leaves the old bucket and adds nothing
@ops.dept = ''
@ops.save
@ops.update_in_bv_co_dept_index(@co, 'ops')
[@client.exists('bv_co:c-1:dept_index'), @co.find_all_by_dept('ops'), @ops.send(:_index_scope_tracker).hgetall]
#=> [0, [], { "bv_co\tdept_index\tc-1\t" => '' }]

## update_in_* from a blank value removes a member written there before
@co.dept_index_for('').add('e3')
@ops.dept = 'ops'
@ops.save
@ops.update_in_bv_co_dept_index(@co, '')
[@client.smembers('bv_co:c-1:dept_index'), @co.find_all_by_dept('ops').map(&:eid)]
#=> [[], ["e3"]]

## The audit reports a blank-value bucket left by earlier writes, and health_check counts it
@co.dept_index_for('').add('e1')
@co.dept_index_for('').add('e3')
@scoped = BvEmp.audit_multi_indexes.first
[
  @scoped[:status],
  @scoped[:orphaned_keys],
  @scoped[:stale_members].map { |entry| entry.values_at(:indexed_id, :reason, :current_value) },
  @scoped[:missing],
  BvEmp.health_check.healthy?,
]
#=> [:issues_found, [{ field_value: '', key: 'bv_co:c-1:dept_index', scope_id: 'c-1', reason: :field_value_unheld }], [["e3", :value_mismatch, "ops"]], [], false]

## The rebuild deletes the blank-value bucket and keeps the others
@cleared = []
@count = @co.rebuild_dept_index { |progress| @cleared << progress[:key] if progress[:key] }
[@count, @cleared.sort, @client.exists('bv_co:c-1:dept_index'), @co.find_all_by_dept('ops').map(&:eid)]
#=> [3, ["bv_co:c-1:dept_index", "bv_co:c-1:dept_index:ops", "bv_co:c-1:dept_index:sales"], 0, ["e3"]]

## After the rebuild the index is healthy
[BvEmp.audit_multi_indexes.first[:status], BvEmp.health_check.healthy?]
#=> [:ok, true]

## repair_multi_indexes! deletes a blank-value bucket too
@co.dept_index_for('').add('e1')
[BvEmp.repair_multi_indexes![:rebuilt_per_scope], @client.exists('bv_co:c-1:dept_index')]
#=> [[{ index_name: :dept_index, scopes_rebuilt: 1 }], 0]

## The blank-value bucket of a scope whose identifier starts with "<scope>:<index>:" is that scope's
# "bv_co:c-1:dept_index:x:dept_index" is both the bucket of value
# "x:dept_index" in scope "c-1" and the blank-value bucket of scope
# "c-1:dept_index:x". The longer identifier wins.
@long = BvCo.new(cid: 'c-1:dept_index:x')
@long.save
@long.dept_index_for('').add('e1')
@long_audit = BvEmp.audit_multi_indexes.first
@co.rebuild_dept_index
[
  @long.dept_index_for('').dbkey,
  @long_audit[:orphaned_keys].map { |entry| entry.values_at(:scope_id, :field_value, :reason) },
  @long_audit[:foreign_owned_keys],
  @client.smembers('bv_co:c-1:dept_index:x:dept_index'),
]
#=> ["bv_co:c-1:dept_index:x:dept_index", [["c-1:dept_index:x", "", :field_value_unheld]], [], ["e1"]]

## That scope's rebuild deletes it
[@long.rebuild_dept_index, @client.exists('bv_co:c-1:dept_index:x:dept_index'), BvEmp.audit_multi_indexes.first[:status]]
#=> [0, 0, :ok]

## The class-level audit reports a blank-value bucket the same way
@admin = BvUser.new(uid: 'u1', role: 'admin')
@admin.save
@nobody = BvUser.new(uid: 'u2', role: '')
@nobody.save
BvUser.rebuild_role_index
BvUser.role_index_for('').add('u1')
@class_audit = BvUser.audit_multi_indexes.first
[
  @class_audit[:status],
  @class_audit[:orphaned_keys],
  @class_audit[:stale_members].map { |entry| entry.values_at(:indexed_id, :reason) },
  BvUser.health_check.healthy?,
]
#=> [:issues_found, [{ field_value: '', key: 'bv_user:role_index' }], [["u1", :value_mismatch]], false]

## The class-level rebuild deletes it
[BvUser.rebuild_role_index, @client.exists('bv_user:role_index'), BvUser.find_all_by_role('admin').map(&:uid), BvUser.audit_multi_indexes.first[:status]]
#=> [2, 0, ["u1"], :ok]

# Teardown
delete_test_dbkeys(BvCo, BvEmp, BvUser)
