# try/bug_fixes/multi_index_rebuild_glob_scope_try.rb
#
# frozen_string_literal: true

# The generated rebuild_<index> for a multi_index clears the existing
# per-value sets with SCAN MATCH and then deletes every match. The pattern
# came from the index set's key with "*" as the field value, e.g.
# "glob_scope_company:c-*:dept_index:*", so glob characters in the scope
# identifier (or, for a class-level index, in the class prefix) were read
# as wildcards. Rebuilding the index of company "c-*" deleted the index
# sets of companies "c-1" and "c-2". The literal part of the pattern is
# now escaped, and a matched key is deleted only if it starts with the
# literal prefix and holds a set. Before it deletes anything, the rebuild
# also checks that every bucket key it will write holds a set or does not
# exist, and raises Familia::IndexBucketConflictError otherwise.

require_relative '../support/helpers/test_helpers'

# Scope class for the instance-scoped index.
class ::GlobScopeCompany < Familia::Horreum
  feature :relationships
  identifier_field :company_id
  field :company_id
end

# Indexed class; its dept_index sets live under each company.
class ::GlobScopeEmployee < Familia::Horreum
  feature :relationships
  identifier_field :emp_id
  field :emp_id
  field :department
  multi_index :department, :dept_index, within: ::GlobScopeCompany
  participates_in ::GlobScopeCompany, :employees
end

# Class-level multi_index whose class prefix holds a glob character, next
# to a rival class whose prefix that unescaped "?" would match.
class ::GlobRoleUser < Familia::Horreum
  prefix 'glob_role?'
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  list :notes
  list :drafts
  sorted_set :scores
  multi_index :role, :role_index
end

# Rival class whose keys the unescaped "glob_role?" prefix matches.
class ::GlobRoleRival < Familia::Horreum
  prefix 'glob_roleX'
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  multi_index :role, :role_index
end

delete_test_dbkeys('glob_scope_company:*', 'glob_scope_employee:*')
delete_test_dbkeys('glob_role\\?:*', 'glob_roleX:*')

# Scope identifiers holding each glob special character, and rival scopes
# whose sets the unescaped pattern of at least one of them would match.
@glob_ids = ['c-*', 'c?1', 'c[12]', 'c\\1', 'c[^x]', 'c[a-z]']
@rival_ids = %w[c-1 c-2 cx1 c1 c2 cy cb]

@companies = {}
(@glob_ids + @rival_ids).each_with_index do |company_id, idx|
  company = GlobScopeCompany.new(company_id: company_id)
  company.save
  employee = GlobScopeEmployee.new(emp_id: "gse-#{idx}", department: 'ops')
  employee.save
  employee.add_to_glob_scope_company_employees(company)
  employee.add_to_glob_scope_company_dept_index(company)
  @companies[company_id] = company
end

@bucket_key = ->(company_id) { "glob_scope_company:#{company_id}:dept_index:ops" }
@dbclient = GlobScopeCompany.dbclient

## every company starts with its own index set
(@glob_ids + @rival_ids).all? { |company_id| @dbclient.exists(@bucket_key.call(company_id)) == 1 }
#=> true

## rebuilding company "c-*" leaves the sets of companies "c-1" and "c-2" alone
@companies['c-*'].rebuild_dept_index
[@dbclient.smembers(@bucket_key.call('c-1')), @dbclient.smembers(@bucket_key.call('c-2'))]
#=> [["gse-6"], ["gse-7"]]

## rebuilding each glob-named company leaves every other company's set alone
@glob_ids.each { |company_id| @companies[company_id].rebuild_dept_index }
(@glob_ids + @rival_ids).reject { |company_id| @dbclient.exists(@bucket_key.call(company_id)) == 1 }
#=> []

## the clearing phase reports only the rebuilt company's own keys
@cleared = []
@companies['c[12]'].rebuild_dept_index do |progress|
  @cleared << progress[:key] if progress[:phase] == :clearing && progress[:key]
end
@cleared
#=> ["glob_scope_company:c[12]:dept_index:ops"]

## the rebuild still clears an orphaned set of its own scope and rebuilds the live one
@glob_company = @companies['c-*']
@glob_company.dept_index_for('legacy').add('gse-ghost')
@processed = @glob_company.rebuild_dept_index
[@processed, @glob_company.dept_index_for('legacy').exists?, @glob_company.dept_index_for('ops').members]
#=> [1, false, ["gse-0"]]

## a key under the scope's index prefix that is not a set is not deleted
@dbclient.set('glob_scope_company:c-1:dept_index:note', 'not an index set')
@companies['c-1'].rebuild_dept_index
@dbclient.get('glob_scope_company:c-1:dept_index:note')
#=> "not an index set"

## the instance-scoped audit skips a key under a scope's index prefix that is not a set
@dbclient.set('glob_scope_company:c-2:dept_index:memo', 'not an index set')
GlobScopeEmployee.audit_multi_indexes.map { |result| result.values_at(:index_name, :status) }
#=> [[:dept_index, :ok]]

## repair_multi_indexes! audits and rebuilds every scope and keeps the non-set keys
@companies['c-1'].dept_index_for('legacy').add('gse-ghost')
@repaired = GlobScopeEmployee.repair_multi_indexes!
[
  @repaired[:rebuilt_per_scope],
  @dbclient.get('glob_scope_company:c-1:dept_index:note'),
  @dbclient.get('glob_scope_company:c-2:dept_index:memo'),
  @companies['c-1'].dept_index_for('legacy').exists?,
]
#=> [[{ index_name: :dept_index, scopes_rebuilt: 13 }], "not an index set", "not an index set", false]

## a scope identifier with invalid UTF-8 bytes is rebuilt and its rival keeps its set
@bad_companies = ["bad\xFF-*", "bad\xFF-1"].each_with_index.map do |company_id, idx|
  company = GlobScopeCompany.new(company_id: company_id)
  company.save
  employee = GlobScopeEmployee.new(emp_id: "gsb-#{idx}", department: 'ops')
  employee.save
  employee.add_to_glob_scope_company_employees(company)
  employee.add_to_glob_scope_company_dept_index(company)
  company
end
[
  @bad_companies.first.rebuild_dept_index,
  @bad_companies.map { |company| @dbclient.smembers(@bucket_key.call(company.company_id)) },
]
#=> [1, [["gsb-0"], ["gsb-1"]]]

## a rebuild raises before it deletes anything when a key it must write holds another type
@glob_company = @companies['c-*']
@eng_employee = GlobScopeEmployee.new(emp_id: 'gse-eng', department: 'eng')
@eng_employee.save
@eng_employee.add_to_glob_scope_company_employees(@glob_company)
@eng_employee.add_to_glob_scope_company_dept_index(@glob_company)
@ops_key = @bucket_key.call('c-*')
@dbclient.del(@ops_key)
@dbclient.zadd(@ops_key, 1, 'gse-0')
begin
  @glob_company.rebuild_dept_index(batch_size: 1)
rescue Familia::IndexBucketConflictError => e
  @conflict = e
end
[@conflict&.conflicts, @glob_company.dept_index_for('eng').members, @dbclient.type(@ops_key)]
#=> [{ "glob_scope_company:c-*:dept_index:ops" => "zset" }, ["gse-eng"], "zset"]

## the error message names each conflicting key and its type, and what the rebuild needs
@conflict.message
#=> 'Multi-index bucket keys hold a type other than set: "glob_scope_company:c-*:dept_index:ops" (zset). The rebuild stopped before it deleted or wrote anything. It can run once each of these keys holds a set or no longer exists.'

## the stopped rebuild left the rival scopes' sets alone
[@dbclient.smembers(@bucket_key.call('c-1')), @dbclient.smembers(@bucket_key.call('c-2'))]
#=> [["gse-6"], ["gse-7"]]

## once the conflicting key is gone the rebuild completes
@dbclient.del(@ops_key)
[@glob_company.rebuild_dept_index, @glob_company.dept_index_for('ops').members, @glob_company.dept_index_for('eng').members]
#=> [2, ["gse-0"], ["gse-eng"]]

## the class-level rebuild of a glob-prefixed class leaves the rival class's sets alone
GlobRoleUser.new(uid: 'gru-1', role: 'admin').save
GlobRoleRival.new(uid: 'grr-1', role: 'admin').save
GlobRoleUser.rebuild_role_index
[GlobRoleRival.role_index_for('admin').members, GlobRoleUser.role_index_for('admin').members]
#=> [["grr-1"], ["gru-1"]]

## the class-level rebuild keeps the hash, list and sorted set of a record named after the index
@victim = GlobRoleUser.new(uid: 'role_index', role: 'member')
@victim.save
@victim.notes.push('keep me')
@victim.scores.add('keep me too', 1)
GlobRoleUser.rebuild_role_index
[
  GlobRoleUser.exists?('role_index'),
  @victim.notes.members,
  @victim.scores.members,
  GlobRoleUser.role_index_for('member').members,
]
#=> [true, ["keep me"], ["keep me too"], ["role_index"]]

## the class-level audit skips the hash and list of a record named after the index
@victim.save
GlobRoleUser.audit_multi_indexes.map { |result| result.values_at(:index_name, :status) }
#=> [[:role_index, :ok]]

## repair_multi_indexes! audits, rebuilds and keeps the record named after the index
GlobRoleUser.role_index_for('ghost').add('nobody')
@repaired = GlobRoleUser.repair_multi_indexes!
[
  @repaired[:rebuilt],
  GlobRoleUser.exists?('role_index'),
  @victim.notes.members,
  GlobRoleUser.role_index_for('ghost').exists?,
]
#=> [[:role_index], true, ["keep me"], false]

## health_check completes with the record named after the index
GlobRoleUser.health_check.multi_indexes.map { |result| result.values_at(:index_name, :status) }
#=> [[:role_index, :ok]]

## repair_all! completes and keeps the record named after the index
[GlobRoleUser.repair_all!.values_at(:status, :errors), GlobRoleUser.exists?('role_index')]
#=> [[:ok, {}], true]

## a class-level rebuild raises before it deletes anything when a live value's key is a record's list
@role_client = GlobRoleUser.dbclient
GlobRoleUser.new(uid: 'gru-drafts', role: 'drafts').save
@role_client.del(GlobRoleUser.role_index_for('drafts').dbkey)
@victim.drafts.push('draft 1')
begin
  GlobRoleUser.rebuild_role_index
rescue Familia::IndexBucketConflictError => e
  @class_conflict = e
end
[
  @class_conflict&.conflicts,
  @victim.drafts.members,
  GlobRoleUser.role_index_for('admin').members,
  GlobRoleUser.role_index_for('member').members,
]
#=> [{ "glob_role?:role_index:drafts" => "list" }, ["draft 1"], ["gru-1"], ["role_index"]]

## repair_multi_indexes! raises the same conflict error and keeps the list
begin
  GlobRoleUser.repair_multi_indexes!
rescue Familia::IndexBucketConflictError => e
  [e.conflicts, @victim.drafts.members, GlobRoleUser.role_index_for('admin').members]
end
#=> [{ "glob_role?:role_index:drafts" => "list" }, ["draft 1"], ["gru-1"]]

## repair_all! reports the conflict as a failed multi-index stage and keeps the list
@repair_result = GlobRoleUser.repair_all!
[
  @repair_result[:status],
  @repair_result[:errors].transform_values { |error| error[:class] },
  @victim.drafts.members,
]
#=> [:partial_failure, { multi_indexes: "Familia::IndexBucketConflictError" }, ["draft 1"]]

delete_test_dbkeys('glob_scope_company:*', 'glob_scope_employee:*')
delete_test_dbkeys('glob_role\\?:*', 'glob_roleX:*')
