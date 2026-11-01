# try/integration/futures/relationships_futures_try.rb
#
# frozen_string_literal: true

# Relationship query and staging methods inside transaction,
# atomic_write and pipelined blocks. They load records, scan, or derive an
# answer from reply contents, so inside a block they raise
# Familia::OperationModeError before issuing anything that matters. Thin
# collection wrappers pass the command's Redis::Future through. See
# docs/reference/transaction_safety.md for the policy these tests pin.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# These fixture classes belong to one scenario, so they share this file.
# rubocop:disable Style/OneClassPerFile
# Scope for the instance-scoped indexes and the participation collection.
class FuturesRelCompany < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :company_id
  field :company_id
  field :name
end

# Join model for the staged participation.
class FuturesRelMembership < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :objid
  field :futures_rel_company_objid
  field :futures_rel_invitee_objid
  field :role
  field :created_at
  field :updated_at
end

# Indexed participant: one index of every kind plus a staged participation.
class FuturesRelEmployee < Familia::Horreum
  feature :object_identifier
  feature :external_identifier
  feature :relationships
  identifier_field :emp_id
  field :emp_id
  field :email
  field :badge
  field :dept
  field :role
  unique_index :email, :email_lookup
  unique_index :badge, :badge_index, within: FuturesRelCompany
  multi_index :dept, :dept_index
  multi_index :role, :role_index, within: FuturesRelCompany
  participates_in FuturesRelCompany, :staff
  participates_in FuturesRelCompany, :queue, type: :list
end

# Participant in a staged, through-model collection.
class FuturesRelInvitee < Familia::Horreum
  feature :object_identifier
  feature :relationships
  identifier_field :invitee_id
  field :invitee_id
  participates_in FuturesRelCompany, :members, through: FuturesRelMembership, staged: :pending_members
end
# rubocop:enable Style/OneClassPerFile

delete_test_dbkeys(FuturesRelCompany, FuturesRelEmployee, FuturesRelMembership, FuturesRelInvitee)

@company = FuturesRelCompany.new(company_id: 'frc-1', name: 'Acme')
@company.save
@emp = FuturesRelEmployee.new(emp_id: 'fre-1', email: 'e1@example.com', badge: 'B1', dept: 'eng', role: 'dev')
@emp.save
@emp.add_to_futures_rel_company_badge_index(@company)
@emp.add_to_futures_rel_company_role_index(@company)
@emp.add_to_futures_rel_company_staff(@company)
@emp.add_to_futures_rel_company_queue(@company)
@staged = @company.stage_members_instance(through_attrs: { role: 'viewer' })

# Runs the block inside atomic_write next to a scalar field change and
# returns [block result, name as persisted after the block].
@in_atomic_write = lambda do |name, &blk|
  captured = nil
  @company.atomic_write do
    @company.name = name
    captured = blk.call
  end
  [captured, FuturesRelCompany.load('frc-1').name]
end

@in_pipeline = lambda do |&blk|
  captured = nil
  FuturesRelCompany.pipelined { captured = blk.call }
  captured
end

@refused = lambda do |&blk|
  blk.call
  :no_error
rescue StandardError => e
  e.class
end

## class-level unique index finders inside atomic_write raise and persist nothing
@results = [
  @refused.call { @in_atomic_write.call('aw-find') { FuturesRelEmployee.find_by_email('e1@example.com') } },
  @refused.call { @in_atomic_write.call('aw-find') { FuturesRelEmployee.find_all_by_email(['e1@example.com']) } },
  @refused.call { @in_atomic_write.call('aw-find') { FuturesRelEmployee.rebuild_email_lookup } },
]
[@results.uniq, FuturesRelCompany.load('frc-1').name]
#=> [[Familia::OperationModeError], "Acme"]

## class-level unique index finders and guard inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { FuturesRelEmployee.find_by_email('e1@example.com') } },
  @refused.call { @in_pipeline.call { FuturesRelEmployee.find_all_by_email(['e1@example.com']) } },
  @refused.call { @in_pipeline.call { @emp.guard_unique_email_lookup! } },
].uniq
#=> [Familia::OperationModeError]

## instance-scoped unique index finders inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-scoped') { @company.find_by_badge('B1') } },
  @refused.call { @in_atomic_write.call('aw-scoped') { @company.find_all_by_badge(['B1']) } },
  @refused.call { @in_atomic_write.call('aw-scoped') { @emp.guard_unique_futures_rel_company_badge_index!(@company) } },
].uniq
#=> [Familia::OperationModeError]

## instance-scoped unique index rebuild inside a pipeline raises OperationModeError
@refused.call { @in_pipeline.call { @company.rebuild_badge_index } }
#=> Familia::OperationModeError

## multi index finders inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-multi') { FuturesRelEmployee.find_all_by_dept('eng') } },
  @refused.call { @in_atomic_write.call('aw-multi') { FuturesRelEmployee.sample_from_dept('eng') } },
  @refused.call { @in_atomic_write.call('aw-multi') { @company.find_all_by_role('dev') } },
  @refused.call { @in_atomic_write.call('aw-multi') { @company.sample_from_role('dev') } },
].uniq
#=> [Familia::OperationModeError]

## multi index rebuilds inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { FuturesRelEmployee.rebuild_dept_index } },
  @refused.call { @in_pipeline.call { @company.rebuild_role_index } },
].uniq
#=> [Familia::OperationModeError]

## participation queries inside atomic_write raise OperationModeError
[
  @refused.call { @in_atomic_write.call('aw-part') { @emp.futures_rel_company_ids } },
  @refused.call { @in_atomic_write.call('aw-part') { @emp.futures_rel_company_count } },
  @refused.call { @in_atomic_write.call('aw-part') { @emp.futures_rel_company? } },
  @refused.call { @in_atomic_write.call('aw-part') { @emp.futures_rel_company_instances } },
  @refused.call { @in_atomic_write.call('aw-part') { @emp.current_participations } },
  @refused.call { @in_atomic_write.call('aw-part') { @emp.position_in_futures_rel_company_queue(@company) } },
].uniq
#=> [Familia::OperationModeError]

## participation readers and validate_relationships! name themselves in the error
@names = []
[
  -> { @emp.futures_rel_company_ids },
  -> { @emp.futures_rel_company_count },
  -> { @emp.futures_rel_company? },
  -> { @emp.futures_rel_company_instances },
  -> { @emp.validate_relationships! },
].each do |call|
  @in_pipeline.call(&call)
rescue Familia::OperationModeError => e
  @names << e.message[/#(\w+[?!]?) cannot run inside/, 1]
end
@expected_names = %w[
  futures_rel_company_ids futures_rel_company_count futures_rel_company?
  futures_rel_company_instances validate_relationships!
]
@names == @expected_names
#=> true

## current_indexings and relationship_status inside a pipeline raise OperationModeError
# The record was never saved, so no index holds it. Each membership check
# would be a truthy Redis::Future and report every index.
@unsaved = FuturesRelEmployee.new(emp_id: 'fre-unsaved', email: 'nobody@example.com', dept: 'ops')
[
  @refused.call { @in_pipeline.call { @unsaved.current_indexings } },
  @refused.call { @in_pipeline.call { @unsaved.relationship_status } },
].uniq
#=> [Familia::OperationModeError]

## current_indexings inside a transaction raises OperationModeError
@refused.call { @company.transaction { @unsaved.current_indexings } }
#=> Familia::OperationModeError

## indexed_in? inside a pipeline passes the membership Futures through
@ret = @in_pipeline.call { [@unsaved.indexed_in?(:email_lookup), @emp.indexed_in?(:dept_index)] }
[@ret.map(&:class).uniq, @ret.map(&:value)]
#=> [[Redis::Future], [false, true]]

## index format checks inside a block raise OperationModeError before sampling
@email_idx = Familia.unique_indexes(owner: FuturesRelEmployee, class_level: true).first
[
  @refused.call { @in_pipeline.call { @email_idx.stale_format? } },
  @refused.call { @in_pipeline.call { @email_idx.format_current? } },
  @refused.call { @company.transaction { Familia.stale_indexes(owner: FuturesRelEmployee) } },
  @refused.call { @company.transaction { Familia.assert_indexes_current!(owner: FuturesRelEmployee) } },
].uniq
#=> [Familia::OperationModeError]

## index format checks name themselves in the error
@names = []
[
  -> { @email_idx.stale_format? },
  -> { @email_idx.format_current? },
  -> { Familia.stale_indexes(owner: FuturesRelEmployee) },
  -> { Familia.assert_indexes_current!(owner: FuturesRelEmployee) },
].each do |call|
  @in_pipeline.call(&call)
rescue Familia::OperationModeError => e
  @names << e.message[/\A(\S+) cannot run inside/, 1]
end
@names == %w[
  IndexDescriptor#stale_format? IndexDescriptor#format_current?
  Familia.stale_indexes Familia.assert_indexes_current!
]
#=> true

## permission queries inside a pipeline raise OperationModeError
[
  @refused.call { @in_pipeline.call { @company.staff_with_permission(:read) } },
  @refused.call { @in_pipeline.call { @company.each_staff_with_permission(:read) { |_m| nil } } },
].uniq
#=> [Familia::OperationModeError]

## membership check and score inside atomic_write pass Futures through
@ret, @persisted = @in_atomic_write.call('aw-member') do
  [@emp.in_futures_rel_company_staff?(@company), @emp.score_in_futures_rel_company_staff(@company)]
end
[@ret.map(&:class).uniq, @ret.first.value, @ret.last.value.is_a?(Float), @persisted]
#=> [[Redis::Future], 0, true, "aw-member"]

## list membership check and score inside a pipeline pass the LPOS and ZSCORE Futures through
@ret = @in_pipeline.call do
  [@emp.in_futures_rel_company_queue?(@company), @emp.score_in_futures_rel_company_staff(@company)]
end
[@ret.map(&:class).uniq, @ret.first.value, @ret.last.value.is_a?(Float)]
#=> [[Redis::Future], 0, true]

## unstaging inside a transaction raises before queueing, so a rescued error commits nothing
@err = nil
@company.transaction do
  @company.unstage_members_instance(@staged)
rescue Familia::OperationModeError => e
  @err = e
end
[@err.message.include?('FuturesRelCompany#unstage_members_instance cannot run inside'),
 @staged.exists?, @company.pending_members.member?(@staged.objid)]
#=> [true, true, true]

## activating inside a transaction raises before queueing, so a rescued error commits nothing
@invitee = FuturesRelInvitee.new(invitee_id: 'fri-1')
@invitee.save
@err = nil
@company.transaction do
  @company.activate_members_instance(@staged, @invitee)
rescue Familia::OperationModeError => e
  @err = e
end
[@err.message.include?('FuturesRelCompany#activate_members_instance cannot run inside'),
 @company.members.member?(@invitee), @company.pending_members.member?(@staged.objid), @staged.exists?]
#=> [true, false, true, true]

## staging and bulk unstaging inside a transaction or pipeline raise OperationModeError
@results = [
  @refused.call { @company.transaction { @company.stage_members_instance(through_attrs: { role: 'viewer' }) } },
  @refused.call { @in_pipeline.call { @company.stage_members([{ role: 'viewer' }]) } },
  @refused.call { @company.transaction { @company.unstage_members([@staged]) } },
  @refused.call { @in_pipeline.call { @company.unstage_members([@staged]) } },
]
[@results.size, @results.uniq, @company.pending_members.size, @staged.exists?]
#=> [4, [Familia::OperationModeError], 1, true]

## staging inside a transaction names the generated method in the error
@err = nil
begin
  @company.transaction { @company.stage_members_instance(through_attrs: {}) }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.include?('FuturesRelCompany#stage_members_instance cannot run inside')
#=> true

## through-model adds and removes inside a transaction raise before queueing, so rescued errors commit nothing
@member = FuturesRelInvitee.new(invitee_id: 'fri-2')
@member.save
@memberships_before = FuturesRelMembership.instances.size
@errors = []
@company.transaction do
  [
    -> { @company.add_members_instance(@member) },
    -> { @company.remove_members_instance(@member) },
    -> { @member.add_to_futures_rel_company_members(@company) },
    -> { @member.remove_from_futures_rel_company_members(@company) },
  ].each do |call|
    call.call
  rescue Familia::OperationModeError => e
    @errors << e.message[/(\w+#\w+) cannot run inside/, 1]
  end
end
@expected_names = %w[
  FuturesRelCompany#add_members_instance FuturesRelCompany#remove_members_instance
  FuturesRelInvitee#add_to_futures_rel_company_members FuturesRelInvitee#remove_from_futures_rel_company_members
]
[@errors == @expected_names, @company.members.member?(@member),
 FuturesRelMembership.instances.size == @memberships_before]
#=> [true, false, true]

## the instance-scoped guard names itself in the error
@err = nil
begin
  FuturesRelCompany.pipelined { @emp.guard_unique_futures_rel_company_badge_index!(@company) }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.include?('#guard_unique_futures_rel_company_badge_index! cannot run inside')
#=> true

## unique index writers and claims inside a pipeline name themselves and queue nothing
@writer_calls = {
  'add_to_futures_rel_company_badge_index' => -> { @emp.add_to_futures_rel_company_badge_index(@company) },
  'update_in_futures_rel_company_badge_index' => -> { @emp.update_in_futures_rel_company_badge_index(@company, 'B0') },
  'add_to_class_email_lookup' => -> { @emp.add_to_class_email_lookup },
  'update_in_class_email_lookup' => -> { @emp.update_in_class_email_lookup('e0@example.com') },
  'claim_unique_email_lookup!' => -> { @emp.claim_unique_email_lookup! },
}
@writer_outcomes = @writer_calls.map do |name, call|
  err = nil
  result = FuturesRelCompany.pipelined do
    call.call
  rescue StandardError => e
    err = e
  end
  [err.class, err.message.include?("FuturesRelEmployee##{name} cannot run inside"), result.results]
end
@writer_outcomes.uniq
#=> [[Familia::OperationModeError, true, []]]

## the class-level claim inside a transaction names itself too
@err = nil
begin
  FuturesRelEmployee.transaction { @emp.claim_unique_email_lookup! }
rescue Familia::OperationModeError => e
  @err = e
end
@err.message.include?('FuturesRelEmployee#claim_unique_email_lookup! cannot run inside')
#=> true

## the instance-scoped add_to_* inside a transaction still writes without a check
@emp2 = FuturesRelEmployee.new(emp_id: 'fre-2', email: 'e2@example.com', badge: 'B2', dept: 'ops', role: 'ops')
@emp2.save
FuturesRelCompany.transaction { @emp2.add_to_futures_rel_company_badge_index(@company) }
@company.find_by_badge('B2').emp_id
#=> "fre-2"

## destroy! of a record with instance-scoped indexes inside a transaction raises and keeps it
[@refused.call { @emp.transaction { @emp.destroy! } }, @emp.exists?, @company.find_by_badge('B1').emp_id]
#=> [Familia::OperationModeError, true, "fre-1"]

## destroy! inside a transaction names destroy! in the error, not the tracker read
@err = nil
begin
  @emp.transaction { @emp.destroy! }
rescue Familia::OperationModeError => e
  @err = e
end
[@err.message.include?('FuturesRelEmployee#destroy! cannot run inside'),
 @err.message.include?('read_instance_index_scopes')]
#=> [true, false]

## destroy! refuses before queueing the objid and extid lookup deletes, so a rescued error commits nothing
@err = nil
@destroy_result = @emp.transaction do
  @emp.destroy!
rescue Familia::OperationModeError => e
  @err = e
end
[@err.class, @destroy_result.results, @emp.exists?,
 FuturesRelEmployee.find_by_objid(@emp.objid)&.emp_id, FuturesRelEmployee.find_by_extid(@emp.extid)&.emp_id]
#=> [Familia::OperationModeError, [], true, "fre-1", "fre-1"]

## destroy! refuses before queueing inside a pipeline too
@err = nil
@destroy_result = @emp.pipelined do
  @emp.destroy!
rescue Familia::OperationModeError => e
  @err = e
end
[@err.class, @destroy_result.results, FuturesRelEmployee.find_by_objid(@emp.objid)&.emp_id]
#=> [Familia::OperationModeError, [], "fre-1"]

## destroy! of a record without instance-scoped indexes still queues inside a transaction
@plain = FuturesRelCompany.new(company_id: 'frc-2', name: 'Plain')
@plain.save
@plain.transaction { @plain.destroy! }
@plain.exists?
#=> false

## outside a block: index finders still load records
[FuturesRelEmployee.find_by_email('e1@example.com').emp_id, @company.find_by_badge('B1').emp_id,
 FuturesRelEmployee.find_all_by_dept('eng').map(&:emp_id), @company.find_all_by_role('dev').map(&:emp_id)]
#=> ["fre-1", "fre-1", ["fre-1"], ["fre-1"]]

## outside a block: participation queries still answer
[@emp.futures_rel_company_ids, @emp.futures_rel_company_count, @emp.futures_rel_company?,
 @emp.in_futures_rel_company_staff?(@company), @emp.position_in_futures_rel_company_queue(@company)]
#=> [["frc-1"], 1, true, true, 0]

## outside a block: list membership and score still answer with a Boolean and a Float
[@emp.in_futures_rel_company_queue?(@company), @emp.score_in_futures_rel_company_staff(@company).class]
#=> [true, Float]

## outside a block: index format checks still answer
[@email_idx.stale_format?, @email_idx.format_current?, Familia.stale_indexes(owner: FuturesRelEmployee),
 Familia.assert_indexes_current!(owner: FuturesRelEmployee)]
#=> [false, true, [], true]

## outside a block: current_indexings reports only the class-level indexes that hold the record
[@unsaved.current_indexings,
 @emp.current_indexings.select { |m| m[:scope_class] == 'class' }.map { |m| m[:index_name] }.sort]
#=> [[], [:dept_index, :email_lookup]]

## outside a block: through-model adds and removes still run
@through = @company.add_members_instance(@member)
@added = [@through.class, @company.members.member?(@member)]
@company.remove_members_instance(@member)
[@added, @company.members.member?(@member), @through.exists?]
#=> [[FuturesRelMembership, true], false, false]

## outside a block: activation logs a staging entry only when it was already gone
# activate_*_instance removes the staging entry inside its own transaction,
# so it reads the ZREM reply after that transaction completes.
@activate_logging = lambda do |staged, participant|
  log_io = StringIO.new
  orig_logger = Familia.logger
  Familia.logger = Familia::FamiliaLogger.new(log_io)
  Familia.debug = true
  begin
    @company.activate_members_instance(staged, participant)
  ensure
    Familia.debug = false
    Familia.logger = orig_logger
  end
  log_io.string.include?("Staging entry not found for #{staged.objid}")
end
@present = @company.stage_members_instance(through_attrs: { role: 'viewer' })
@gone = @company.stage_members_instance(through_attrs: { role: 'viewer' })
@company.pending_members.remove(@gone.objid)
@first = FuturesRelInvitee.new(invitee_id: 'fri-3')
@first.save
@second = FuturesRelInvitee.new(invitee_id: 'fri-4')
@second.save
[@activate_logging.call(@present, @first), @activate_logging.call(@gone, @second)]
#=> [false, true]

## outside a block: unstaging still runs
[@company.unstage_members_instance(@staged), @staged.exists?]
#=> [true, false]

# Teardown
delete_test_dbkeys(FuturesRelCompany, FuturesRelEmployee, FuturesRelMembership, FuturesRelInvitee)
