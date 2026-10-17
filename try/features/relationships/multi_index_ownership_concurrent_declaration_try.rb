# try/features/relationships/multi_index_ownership_concurrent_declaration_try.rb
#
# frozen_string_literal: true

# The multi_index rebuild and audit read the set field names of the scope
# class (RecordKeyOwnership.record_set_key_names) to decide which record a
# bucket key belongs to. They read a snapshot of the related-field registry,
# so a field declared in another thread while they read it does not raise
# "can't add a new key into hash during iteration".

require 'timeout'

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Options Hash of a related field that blocks once on its :dbkey lookup,
# which record_set_key_names reads for every related field.
class MocBlockingOptions < Hash
  def initialize(control)
    @control = control
    super()
  end

  def [](key)
    if key == :dbkey && @control[:armed].true?
      @control[:armed].make_false
      @control[:entered] << true
      @control[:release].pop
    end
    super
  end
end

class MocCompany < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
  set :tags
end

class MocEmployee < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: MocCompany
  participates_in MocCompany, :staff
end

delete_test_dbkeys(MocCompany, MocEmployee)

@control = {
  armed: Concurrent::AtomicBoolean.new(false),
  entered: Queue.new,
  release: Queue.new,
}
@tags_definition = MocCompany.related_fields.fetch(:tags)
@blocking_options = MocBlockingOptions.new(@control)
@blocking_options.merge!(@tags_definition.opts)
MocCompany.related_fields_mutex.synchronize do
  MocCompany.related_fields[:tags] = @tags_definition.with(opts: @blocking_options)
end

@company = MocCompany.new(cid: 'c-1')
@company.save
@employee = MocEmployee.new(eid: 'e1', dept: 'ops')
@employee.save
@employee.add_to_moc_company_staff(@company)

# Runs +work+ in a thread, waits until it reads the :dbkey option of the
# tags field, declares +field_name+ on MocCompany from another thread, then
# lets +work+ finish. Returns the work's result or error, the declaration
# error, and whether the field was declared.
@race = lambda do |field_name, &work|
  result = nil
  work_error = nil
  declaration_error = nil
  @control[:armed].make_true
  worker = Thread.new do
    result = work.call
  rescue StandardError => e
    work_error = e
  end
  begin
    Timeout.timeout(5) { @control[:entered].pop }
    Thread.new do
      MocCompany.set field_name
    rescue StandardError => e
      declaration_error = e
    end.join
  rescue Timeout::Error => e
    work_error ||= e
  ensure
    @control[:release] << true
    worker.join
  end
  [result, work_error&.class, declaration_error&.class, MocCompany.related_fields.key?(field_name)]
end

## A rebuild tolerates a set field declared while it reads the field names
@race.call(:late_rebuild) { @company.rebuild_dept_index }
#=> [1, nil, nil, true]

## An audit tolerates a set field declared while it reads the field names
@race.call(:late_audit) { MocEmployee.audit_multi_indexes.first[:status] }
#=> [:ok, nil, nil, true]

## The rebuild still keeps the indexed member afterwards
[@company.rebuild_dept_index, @company.find_all_by_dept('ops').map(&:eid)]
#=> [1, ["e1"]]

# Teardown
@control[:armed].make_false
delete_test_dbkeys(MocCompany, MocEmployee)
