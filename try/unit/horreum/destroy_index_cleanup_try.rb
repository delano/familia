# try/unit/horreum/destroy_index_cleanup_try.rb
#
# frozen_string_literal: true

# Horreum destroy! Class-Level Index Cleanup Tryouts
#
# Reproduces GitHub issue #241: `Horreum#destroy!` removes the object hash,
# related fields, and the entry from the class-level `instances` sorted set,
# but does NOT remove entries from class-level `unique_index` hashes or
# `multi_index` sets. Stale `email_index[value] -> objid` entries persist
# after destroy and cause `RecordExistsError` on the next `create!` with
# the same indexed value.
#
# Scope: class-level indexes (#241) and instance-scoped indexes (#282).
# Instance-scoped indexes use a reverse index tracker to record scope
# memberships, enabling automatic cleanup on destroy!.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Throwaway test class that exercises both class-level unique and
# multi-index mutation paths. Named with the issue number to avoid
# colliding with any existing test fixtures.
class ::Widget241 < Familia::Horreum
  feature :relationships

  identifier_field :objid
  field :objid
  field :name
  field :category

  # Class-level unique index -- stored as a single HashKey mapping
  # name -> objid. Every object's save auto-populates; destroy! should
  # remove the corresponding entry but currently does not (bug #241).
  unique_index :name, :name_index

  # Class-level multi-index -- stored per-value as an UnsortedSet named
  # `category_index:<value>`. Every object's save auto-populates; destroy!
  # should remove the identifier from the per-value set but currently
  # does not (bug #241).
  multi_index :category, :category_index
end

# Start from a clean slate for indexes so previous test runs don't leak.
Familia.dbclient.flushdb

## Class-level unique_index is populated by save
@w1 = Widget241.create!(objid: 'w241-unique-001', name: 'alpha')
Widget241.name_index.get('alpha')
#=> 'w241-unique-001'

## BUG #241: destroy! leaves a stale entry in the class-level unique_index
# Expected behavior: after destroy!, the `name_index` no longer contains
# an entry for 'alpha' (so a subsequent create! with the same name
# succeeds instead of raising RecordExistsError).
@w1.destroy!
Widget241.name_index.get('alpha')
#=> nil

## BUG #241: re-creating with the same indexed value succeeds after destroy!
# With the stale entry removed, this should not raise RecordExistsError.
@w1b = Widget241.create!(objid: 'w241-unique-002', name: 'alpha')
Widget241.name_index.get('alpha')
#=> 'w241-unique-002'

## Class-level multi_index is populated by save
@m1 = Widget241.create!(objid: 'w241-multi-001', name: 'm-one',   category: 'tools')
@m2 = Widget241.create!(objid: 'w241-multi-002', name: 'm-two',   category: 'tools')
@m3 = Widget241.create!(objid: 'w241-multi-003', name: 'm-three', category: 'tools')
Widget241.category_index_for('tools').members.sort
#=> ['w241-multi-001', 'w241-multi-002', 'w241-multi-003']

## BUG #241: destroy! leaves stale entries in the class-level multi_index
# Expected behavior: after destroying m2, only m1 and m3 remain in the
# per-value set for 'tools' -- m2's identifier should be gone.
@m2.destroy!
Widget241.category_index_for('tools').members.sort
#=> ['w241-multi-001', 'w241-multi-003']

## BUG #241: re-creating with the same multi_index value succeeds after destroy!
# This verifies the per-value set is usable for new members after cleanup.
@m2b = Widget241.create!(objid: 'w241-multi-004', name: 'm-two-again', category: 'tools')
Widget241.category_index_for('tools').members.include?('w241-multi-004')
#=> true

## Regression: destroy! still removes the object hash
# This is the unchanged existing behavior -- confirms we didn't break
# the basic destroy! path while exercising the index cleanup bug.
@r1 = Widget241.create!(objid: 'w241-regress-001', name: 'reg-one', category: 'regress')
@r1.destroy!
Widget241.exists?('w241-regress-001')
#=> false

## Regression: destroy! still removes from the instances timeline
# Another existing guarantee: `remove_from_instances!` runs inside destroy!.
Widget241.in_instances?('w241-regress-001')
#=> false

## Regression: destroy! on a never-persisted object does not raise
# The generated remove_from_class_#{index_name} methods short-circuit via
# `return unless field_value`, so destroying an instance that was never
# saved (all indexed fields still nil) must be a safe no-op.
begin
  Widget241.new(objid: 'w241-unsaved-001').destroy!
  :no_raise
rescue StandardError => e
  "raised: #{e.class.name}"
end
#=> :no_raise

## Regression: destroy! with mixed nil/non-nil indexed fields populates only non-nil index
# A widget with `name` set but `category` nil populates only the unique_index --
# the multi_index's generated add_to_class_* method short-circuits on nil.
@mixed = Widget241.create!(objid: 'w241-mixed-001', name: 'mixed-alpha')
Widget241.name_index.get('mixed-alpha')
#=> 'w241-mixed-001'

## Regression: destroy! with mixed nil/non-nil indexed fields does not raise
# Cleanup must iterate every class-level index and short-circuit cleanly
# when the field value is nil, without raising or leaving stale state.
begin
  @mixed.destroy!
  :no_raise
rescue StandardError => e
  "raised: #{e.class.name}"
end
#=> :no_raise

## Regression: destroy! with mixed fields removed the populated (name) entry
Widget241.name_index.get('mixed-alpha')
#=> nil

## Regression: inverse mixed state -- category set, name nil (asymmetric iteration)
# indexing_relationships.each walks in registration order (name_index first,
# then category_index). This case hits the opposite ordering so the cleanup
# loop exercises a nil unique_index followed by a populated multi_index.
@inverse = Widget241.create!(objid: 'w241-mixed-002', category: 'asymm')
Widget241.category_index_for('asymm').members.include?('w241-mixed-002')
#=> true

## Regression: inverse mixed state destroy! does not raise
begin
  @inverse.destroy!
  :no_raise
rescue StandardError => e
  "raised: #{e.class.name}"
end
#=> :no_raise

## Regression: inverse mixed state destroy! removed the populated (category) entry
Widget241.category_index_for('asymm').members.include?('w241-mixed-002')
#=> false

## Instance-scoped index cleanup via reverse index tracker (#282)
# The #241 fix covered class-level indexes only. Issue #282 adds a
# per-object reverse index tracker (_idx_scopes) that records which
# scope instances hold references. destroy! reads the tracker before
# its MULTI/EXEC transaction, then replays remove_from_* calls inside
# the transaction to clean up instance-scoped entries atomically.
class ::Widget241ScopedCompany < Familia::Horreum
  feature :relationships
  identifier_field :company_id
  field :company_id
end

class ::Widget241ScopedEmployee < Familia::Horreum
  feature :relationships
  identifier_field :emp_id
  field :emp_id
  field :badge

  # Instance-scoped unique index -- parent context is Widget241ScopedCompany.
  unique_index :badge, :badge_index, within: Widget241ScopedCompany
end

@scope_company = Widget241ScopedCompany.create!(company_id: 'w241co-001')
@scope_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-001', badge: 'B-42')
# Instance-scoped indexes don't auto-populate -- they need the parent context.
@scope_emp.add_to_widget241scoped_company_badge_index(@scope_company)
@scope_company.badge_index.has_key?('B-42')
#=> true

## BUG #282: destroy! now cleans up instance-scoped index entries
# The reverse index tracker records that scope_emp was added to
# scope_company's badge_index. destroy! reads this tracker, then
# removes the entry inside the same MULTI/EXEC transaction.
@scope_emp.destroy!
@scope_company.badge_index.has_key?('B-42')
#=> false

## Tracker records the indexed VALUE, not just the membership
# The tracker is a HashKey: field is the
# "<scope_config>\t<index_name>\t<scope_id>" identity triple, value is the
# field value that was written into the index. Cleanup needs the value to
# know which bucket to clear, so it is stored at index time.
@val_co = Widget241ScopedCompany.create!(company_id: 'w241co-val')
@val_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-val', badge: 'B-VAL')
@val_emp.add_to_widget241scoped_company_badge_index(@val_co)
@val_emp.send(:_index_scope_tracker).hgetall
#=> { "widget241scoped_company\tbadge_index\tw241co-val" => 'B-VAL' }

## Indexed field changed, then destroy!: nothing is left behind
# save auto-refreshes the tracked entry from 'B-OLD' to 'B-NEW', and the
# tracker follows it, so destroy! clears the bucket the entry actually
# lives in. Before the stored-value tracker, cleanup re-read the current
# field value and could remove the wrong key, orphaning the other.
@chg_co = Widget241ScopedCompany.create!(company_id: 'w241co-chg')
@chg_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-chg', badge: 'B-OLD')
@chg_emp.add_to_widget241scoped_company_badge_index(@chg_co)
@chg_emp.badge = 'B-NEW'
@chg_emp.save
@chg_emp.destroy!
[@chg_co.badge_index.has_key?('B-OLD'), @chg_co.badge_index.has_key?('B-NEW')]
#=> [false, false]

## Auto-refresh on save: the OLD unique value no longer resolves
# The tracked membership is refreshed inside save's transaction, routed
# through update_in_* with the previous value from dirty tracking so the
# stale entry is retracted rather than left as a tombstone.
@ref_co = Widget241ScopedCompany.create!(company_id: 'w241co-ref')
@ref_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-ref', badge: 'B-BEFORE')
@ref_emp.add_to_widget241scoped_company_badge_index(@ref_co)
@ref_emp.badge = 'B-AFTER'
@ref_emp.save
@ref_co.find_by_badge('B-BEFORE')
#=> nil

## Auto-refresh on save: the NEW unique value resolves to the record
@ref_co.find_by_badge('B-AFTER')&.identifier
#=> 'w241emp-ref'

## Auto-refresh on save: the tracker follows the new value
@ref_emp.send(:_index_scope_tracker).hgetall
#=> { "widget241scoped_company\tbadge_index\tw241co-ref" => 'B-AFTER' }

## Auto-refresh frees the old unique value for a different record
# Proves no orphan holds 'B-BEFORE': the uniqueness guard on add_to_*
# raises RecordExistsError if a stale entry is still parked there.
@ref_emp2 = Widget241ScopedEmployee.create!(emp_id: 'w241emp-ref2', badge: 'B-BEFORE')
@ref_emp2.add_to_widget241scoped_company_badge_index(@ref_co)
@ref_co.find_by_badge('B-BEFORE')&.identifier
#=> 'w241emp-ref2'

## save_if_not_exists! prunes tracker entries that outlived the hash (#365)
# The object hash is removed out of band (delete!), leaving tracker entries
# whose index bucket still points here. Entries without a hash can only
# describe a dead incarnation of the identifier, so re-creating via
# save_if_not_exists! removes the old bucket and does NOT re-join the
# scope -- instance-scoped membership stays opt-in for the new record.
@sine_co = Widget241ScopedCompany.create!(company_id: 'w241co-sine')
@sine_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-sine', badge: 'B-SINE')
@sine_emp.add_to_widget241scoped_company_badge_index(@sine_co)
@sine_emp.delete!
@sine_emp.badge = 'B-SINE2'
@sine_emp.save_if_not_exists!
[@sine_co.badge_index.has_key?('B-SINE'), @sine_co.badge_index.has_key?('B-SINE2')]
#=> [false, false]

## The prune clears the tracker itself, leaving a genuinely clean slate
@sine_emp.send(:_index_scope_tracker).hgetall
#=> {}

## save_if_not_exists! re-reads the tracker after a WATCH abort
# The snapshot is taken INSIDE the watched block, so a retry re-reads it
# rather than pruning from a stale copy. Simulated deterministically: the first
# pass touches the watched key (dbkey), which invalidates the WATCH and
# aborts EXEC; the probe counter proves the block ran more than once.
@sir_co = Widget241ScopedCompany.create!(company_id: 'w241co-sir')
@sir_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-sir', badge: 'S-1')
@sir_emp.add_to_widget241scoped_company_badge_index(@sir_co)
@sir_emp.delete!
class << @sir_emp
  attr_accessor :probe_count

  def read_instance_index_scopes
    self.probe_count = (probe_count || 0) + 1
    if probe_count == 1
      # Stand in for a concurrent writer: modify then restore the watched
      # key so EXEC aborts but the existence check still passes on retry.
      Familia.dbclient.hset(dbkey, 'probe', '1')
      Familia.dbclient.hdel(dbkey, 'probe')
    end
    super
  end
end
@sir_emp.badge = 'S-2'
@sir_emp.save_if_not_exists!
@sir_emp.probe_count > 1
#=> true

## The retried save_if_not_exists! still pruned the stale entries correctly
[@sir_co.badge_index.has_key?('S-1'), @sir_co.badge_index.has_key?('S-2')]
#=> [false, false]

## Reused identifier: plain save prunes the previous record's tracker (#365)
# delete! removes only the object hash; the tracker survives. A NEW record
# saved under the same identifier used to replay the stale tracker and
# silently join the scopes the previous record was added to. save now
# detects that the entries outlived the hash (an EXISTS probe, paid only
# when the tracker is non-empty) and prunes them: the dead incarnation's
# bucket is removed and the new record joins nothing.
@reuse_co = Widget241ScopedCompany.create!(company_id: 'w241co-reuse')
@reuse_a = Widget241ScopedEmployee.create!(emp_id: 'w241emp-reuse', badge: 'R-OLD')
@reuse_a.add_to_widget241scoped_company_badge_index(@reuse_co)
@reuse_a.delete!
@reuse_b = Widget241ScopedEmployee.new(emp_id: 'w241emp-reuse', badge: 'R-NEW')
@reuse_b.save
[@reuse_co.badge_index.has_key?('R-OLD'), @reuse_co.badge_index.has_key?('R-NEW')]
#=> [false, false]

## Reused identifier: the tracker is cleared along with the index entries
@reuse_b.send(:_index_scope_tracker).hgetall
#=> {}

## Reused identifier: a fresh add_to_* then behaves like a first membership
# The new record opts in explicitly and gets the ordinary lifecycle,
# destroy! cleanup included.
@reuse_b.add_to_widget241scoped_company_badge_index(@reuse_co)
@reuse_joined = @reuse_co.badge_index.get('R-NEW')
@reuse_b.destroy!
[@reuse_joined, @reuse_co.badge_index.has_key?('R-NEW')]
#=> ['w241emp-reuse', false]

## Reused identifier with a COLLIDING value no longer raises (#365)
# Previously the stale replay tripped the uniqueness guard when the new
# record's value matched another record's entry, failing the save of a
# record that never asked to join the scope. With stale entries pruned
# instead of replayed there is nothing to guard: the save succeeds and the
# other record's entry is untouched.
@col_holder = Widget241ScopedEmployee.create!(emp_id: 'w241emp-col-holder', badge: 'C-HELD')
@col_holder.add_to_widget241scoped_company_badge_index(@reuse_co)
@col_a = Widget241ScopedEmployee.create!(emp_id: 'w241emp-col', badge: 'C-A')
@col_a.add_to_widget241scoped_company_badge_index(@reuse_co)
@col_a.delete!
@col_b = Widget241ScopedEmployee.new(emp_id: 'w241emp-col', badge: 'C-HELD')
@col_b.save
[@reuse_co.badge_index.get('C-HELD'), @reuse_co.badge_index.has_key?('C-A')]
#=> ['w241emp-col-holder', false]

## Same-object save after delete! is also a fresh start (#365)
# Re-saving the very object that was delete!'d (a stand-in for the hash
# expiring via TTL while the tracker survived) goes through the same
# staleness detection: the membership is pruned, not preserved. An object
# whose hash is gone is gone; memberships do not survive death.
@exp_co = Widget241ScopedCompany.create!(company_id: 'w241co-exp')
@exp_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-exp', badge: 'E-1')
@exp_emp.add_to_widget241scoped_company_badge_index(@exp_co)
@exp_emp.delete!
@exp_emp.save
[@exp_co.badge_index.has_key?('E-1'), @exp_emp.send(:_index_scope_tracker).hgetall]
#=> [false, {}]

## atomic_write does NOT refresh instance-scoped indexes (documented gap)
# atomic_write calls persist_to_storage from inside a MULTI it already
# opened, so there is no pre-transaction point at which the tracker could
# be read (HGETALL inside MULTI returns futures). The index keeps the value
# recorded at add_to_* time. This test exists to keep the YARD note honest:
# if atomic_write ever gains a pre-read, this expectation must change.
@aw_co = Widget241ScopedCompany.create!(company_id: 'w241co-aw')
@aw_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-aw', badge: 'B-AW1')
@aw_emp.add_to_widget241scoped_company_badge_index(@aw_co)
@aw_emp.atomic_write { @aw_emp.badge = 'B-AW2' }
[@aw_co.badge_index.get('B-AW1'), @aw_co.badge_index.has_key?('B-AW2')]
#=> ['w241emp-aw', false]

## atomic_write leaves the tracker consistent with the un-refreshed index
# Since neither was touched, destroy! still cleans up correctly.
@aw_emp.destroy!
[@aw_co.badge_index.has_key?('B-AW1'), @aw_co.badge_index.has_key?('B-AW2')]
#=> [false, false]

## DataType rejects an unrecognized dirty_write_warnings mode
# Without the check a typo would fall through warn_if_dirty! to the :once
# branch, silently changing the diagnostic level instead of failing.
begin
  Familia::HashKey.new('dwtest', dirty_write_warnings: :of)
  :no_raise
rescue ArgumentError => e
  e.message.include?('dirty_write_warnings must be one of')
end
#=> true

## DataType keeps an explicit dirty_write_warnings mode (not silently dropped)
# valid_keys_only filters opts against a whitelist, so the option is inert
# unless :dirty_write_warnings is on it. Asserting the resolved mode -- not
# just that construction succeeded -- is what catches that.
[:strict, :warn, :once, :off].map { |m|
  Familia::HashKey.new('dwtest', dirty_write_warnings: m).send(:resolve_dirty_warning_mode)
}
#=> [:strict, :warn, :once, :off]

## Explicit dirty_write_warnings beats the parent class setting
# The DataType-level option is the most specific signal available.
class ::DwModeModel < Familia::Horreum
  identifier_field :dwid
  field :dwid
  dirty_write_warnings :strict
end
@dw_parent = DwModeModel.new(dwid: 'dw-1')
@dw_default = Familia::HashKey.new('dwdefault', parent: @dw_parent)
@dw_explicit = Familia::HashKey.new('dwexplicit', parent: @dw_parent, dirty_write_warnings: :off)
[@dw_default.send(:resolve_dirty_warning_mode), @dw_explicit.send(:resolve_dirty_warning_mode)]
#=> [:strict, :off]

## :off suppresses the raise a :strict parent class would otherwise trigger
# "off means off" -- an explicit :off overrides the raise paths, which is
# exactly what keeps the index tracker writable during save.
@dw_parent.dwid = 'dw-changed'  # make the parent dirty
begin
  @dw_default['k'] = 'v'
  :no_raise
rescue Familia::Problem
  :raised
end
#=> :raised

## :off on the same dirty parent writes without raising
begin
  @dw_explicit['k'] = 'v'
  :no_raise
rescue Familia::Problem
  :raised
end
#=> :no_raise

## :off also overrides the global strict_write_order switch
# This is the setting that would otherwise abort every save that refreshes
# an instance-scoped index.
@dw_prior_strict = Familia.strict_write_order
Familia.strict_write_order = true
@dw_strict_result = begin
  @dw_explicit['k2'] = 'v2'
  :no_raise
rescue Familia::Problem
  :raised
end
Familia.strict_write_order = @dw_prior_strict
@dw_strict_result
#=> :no_raise

## Save-refresh enforces instance-scoped uniqueness (no silent eviction)
# The refresh routes through update_in_*, which has no uniqueness guard --
# only add_to_* did. Without a pre-transaction guard, changing an indexed
# field to a value another record holds silently evicted that record's
# entry, and the evicted record's tracker still claimed the slot, so ITS
# later destroy! unindexed the live winner. Matches the class-level path,
# which always raised.
@dup_co = Widget241ScopedCompany.create!(company_id: 'w241co-dup')
@dup_e1 = Widget241ScopedEmployee.create!(emp_id: 'w241emp-dup1', badge: 'D-1')
@dup_e1.add_to_widget241scoped_company_badge_index(@dup_co)
@dup_e2 = Widget241ScopedEmployee.create!(emp_id: 'w241emp-dup2', badge: 'D-2')
@dup_e2.add_to_widget241scoped_company_badge_index(@dup_co)
@dup_e2.badge = 'D-1'
begin
  @dup_e2.save
  :no_raise
rescue Familia::RecordExistsError
  :record_exists
end
#=> :record_exists

## Duplicate-value save leaves the index completely untouched
# A rejected save must not have partially applied -- the guard runs before
# the transaction opens.
@dup_co.badge_index.hgetall
#=> { 'D-1' => 'w241emp-dup1', 'D-2' => 'w241emp-dup2' }

## The original holder survives destroy! of the rejected record
# This is the corruption the guard prevents: previously D-1 pointed at the
# evicted record, so destroying it removed the live winner's entry.
@dup_e2.destroy!
@dup_co.find_by_badge('D-1')&.identifier
#=> 'w241emp-dup1'

## Renaming to a genuinely free value still refreshes normally
@dup_e1.badge = 'D-FREE'
@dup_e1.save
[@dup_co.find_by_badge('D-1'), @dup_co.find_by_badge('D-FREE')&.identifier]
#=> [nil, 'w241emp-dup1']

## Re-saving without changing the indexed value does not raise
# The guard only inspects changed fields; an unchanged value would
# otherwise be validated against its own entry.
begin
  @dup_e1.save
  :no_raise
rescue Familia::RecordExistsError
  :record_exists
end
#=> :no_raise

## A tab in the scope identifier is rejected before any write
# Tracker entries are tab-delimited and the scope id is an interior
# component, so a tab makes a unique entry byte-identical to a multi entry
# for a DIFFERENT scope -- destroy! would then delete an unrelated scope's
# live index entry.
@tab_co = Widget241ScopedCompany.create!(company_id: "tab\tinjected")
@tab_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-tab', badge: 'T-1')
begin
  @tab_emp.add_to_widget241scoped_company_badge_index(@tab_co)
  :no_raise
rescue ArgumentError => e
  e.message.include?('scope identifier contains a tab')
end
#=> true

## The tab-scoped rejection leaves no tracker entry behind
@tab_emp.send(:_index_scope_tracker).hgetall
#=> {}

## A neighbouring scope whose id is a prefix of the tab id is untouched
# This is the victim in the original report: scope 'tab' vs "tab\tinjected".
@tab_victim_co = Widget241ScopedCompany.create!(company_id: 'tab')
@tab_victim = Widget241ScopedEmployee.create!(emp_id: 'w241emp-tabv', badge: 'T-1')
@tab_victim.add_to_widget241scoped_company_badge_index(@tab_victim_co)
@tab_emp.destroy!
@tab_victim_co.find_by_badge('T-1')&.identifier
#=> 'w241emp-tabv'

## Auto-refresh only touches scopes already registered via add_to_*
# The initial add_to_* stays manual: save has no scope context to invent
# one from, so an unregistered employee is not indexed by saving.
@unreg_co = Widget241ScopedCompany.create!(company_id: 'w241co-unreg')
@unreg_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-unreg', badge: 'B-UNREG')
@unreg_emp.badge = 'B-UNREG2'
@unreg_emp.save
[@unreg_co.badge_index.has_key?('B-UNREG'), @unreg_co.badge_index.has_key?('B-UNREG2')]
#=> [false, false]

## update_in_* re-records the tracker so destroy! follows the value
# Save already refreshed this entry; the explicit update_in_* call is
# idempotent. It moves the index entry to the new value and HSETs the
# tracker, so no old-value bookkeeping is needed and destroy! clears the
# bucket the entry actually lives in.
@upd_co = Widget241ScopedCompany.create!(company_id: 'w241co-upd')
@upd_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-upd', badge: 'B-ONE')
@upd_emp.add_to_widget241scoped_company_badge_index(@upd_co)
@upd_emp.badge = 'B-TWO'
@upd_emp.save
@upd_emp.update_in_widget241scoped_company_badge_index(@upd_co, 'B-ONE')
@before_destroy = [@upd_co.badge_index.has_key?('B-ONE'), @upd_co.badge_index.has_key?('B-TWO')]
@upd_emp.destroy!
[@before_destroy, @upd_co.badge_index.has_key?('B-TWO')]
#=> [[false, true], false]

## update_in_* with a nil field value unrecords instead of recording
# There is no index entry left to clean up, so the tracker entry is dropped
# rather than left pointing at an empty bucket.
@nil_co = Widget241ScopedCompany.create!(company_id: 'w241co-nil')
@nil_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-nil', badge: 'B-GONE')
@nil_emp.add_to_widget241scoped_company_badge_index(@nil_co)
@nil_emp.badge = nil
@nil_emp.save
@nil_emp.update_in_widget241scoped_company_badge_index(@nil_co, 'B-GONE')
[@nil_co.badge_index.has_key?('B-GONE'), @nil_emp.send(:_index_scope_tracker).hgetall]
#=> [false, {}]

## Identifier-only destroy! still cleans up instance-scoped entries
# A freshly constructed instance carrying only the identifier has no
# in-memory field values, so send(:badge) is nil. Cleanup previously
# short-circuited on that nil and orphaned the entry; it now uses the
# value recorded in the tracker.
@idonly_co = Widget241ScopedCompany.create!(company_id: 'w241co-idonly')
@idonly_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-idonly', badge: 'B-IDONLY')
@idonly_emp.add_to_widget241scoped_company_badge_index(@idonly_co)
@idonly_stub = Widget241ScopedEmployee.new(emp_id: 'w241emp-idonly')
@idonly_stub.badge
#=> nil

## Identifier-only destroy! removes the entry recorded by the loaded object
@idonly_stub.destroy!
@idonly_co.badge_index.has_key?('B-IDONLY')
#=> false

## Field values that look like JSON literals round-trip through the tracker
# The tracker stores values JSON-encoded while the index bucket key is
# written raw, so a value like '0' or 'null' must survive the round trip
# or cleanup targets a different key than the write did.
@lit_co = Widget241ScopedCompany.create!(company_id: 'w241co-lit')
@lit_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-lit', badge: '0')
@lit_emp.add_to_widget241scoped_company_badge_index(@lit_co)
@lit_emp2 = Widget241ScopedEmployee.create!(emp_id: 'w241emp-lit2', badge: 'null')
@lit_emp2.add_to_widget241scoped_company_badge_index(@lit_co)
@lit_stub = Widget241ScopedEmployee.new(emp_id: 'w241emp-lit')
@lit_stub2 = Widget241ScopedEmployee.new(emp_id: 'w241emp-lit2')
@lit_stub.destroy!
@lit_stub2.destroy!
[@lit_co.badge_index.has_key?('0'), @lit_co.badge_index.has_key?('null')]
#=> [false, false]

## Instance-scoped multi_index cleanup uses the recorded bucket too
# The multi_index generator stores identifiers in a per-value UnsortedSet,
# so a changed field value means a different key entirely.
class ::Widget282MultiCompany < Familia::Horreum
  feature :relationships
  identifier_field :company_id
  field :company_id
end

class ::Widget282MultiEmployee < Familia::Horreum
  feature :relationships
  identifier_field :emp_id
  field :emp_id
  field :department

  multi_index :department, :dept_index, within: Widget282MultiCompany
end

@multi_co = Widget282MultiCompany.create!(company_id: 'w282mco-001')
@multi_emp = Widget282MultiEmployee.create!(emp_id: 'w282memp-001', department: 'eng')
@multi_emp.add_to_widget282multi_company_dept_index(@multi_co)
@multi_co.dept_index_for('eng').members
#=> ['w282memp-001']

## multi_index: destroy! with no value change clears the recorded bucket
@multi_emp.destroy!
@multi_co.dept_index_for('eng').members
#=> []

## multi_index auto-refresh on save is ADD-ONLY: new bucket gains the id
# Deliberate, and consistent with the class-level multi_index decision
# (see the class_level_multi_index tests): a value change does not retract
# prior buckets. SADD is idempotent, so repeated saves stay safe.
@multi_emp2 = Widget282MultiEmployee.create!(emp_id: 'w282memp-002', department: 'eng')
@multi_emp2.add_to_widget282multi_company_dept_index(@multi_co)
@multi_emp2.department = 'sales'
@multi_emp2.save
@multi_co.dept_index_for('sales').members
#=> ['w282memp-002']

## multi_index auto-refresh on save: the OLD bucket is retained, by design
@multi_co.dept_index_for('eng').members
#=> ['w282memp-002']

## multi_index: the tracker records BOTH buckets the object occupies
# Tracker cardinality mirrors index cardinality: multi entries are keyed by
# scope/index/scope_id/VALUE, so add-only refresh produces one entry per
# bucket rather than a single entry that can only name one of them.
@multi_emp2.send(:_index_scope_tracker).hgetall.keys.sort
#=> ["widget282multi_company\tdept_index\tw282mco-001\teng", "widget282multi_company\tdept_index\tw282mco-001\tsales"]

## multi_index: destroy! clears EVERY bucket the object was in
# The assertion that proves the fix. With a triple-keyed tracker the 'eng'
# bucket was orphaned permanently; per-value entries let destroy! reach
# both.
@multi_emp2.destroy!
[@multi_co.dept_index_for('sales').members, @multi_co.dept_index_for('eng').members]
#=> [[], []]

## multi_index: explicit update_in_* retracts the old bucket and its entry
# Unlike the add-only save refresh, update_in_* with an old value removes
# the object from that bucket -- so the tracker entry for it must go too,
# or the tracker would over-claim a membership that no longer exists.
@upd_multi_emp = Widget282MultiEmployee.create!(emp_id: 'w282memp-003', department: 'eng')
@upd_multi_emp.add_to_widget282multi_company_dept_index(@multi_co)
@upd_multi_emp.department = 'ops'
@upd_multi_emp.save
@upd_multi_emp.update_in_widget282multi_company_dept_index(@multi_co, 'eng')
[@multi_co.dept_index_for('eng').members,
 @multi_co.dept_index_for('ops').members,
 @upd_multi_emp.send(:_index_scope_tracker).hgetall.keys]
#=> [[], ['w282memp-003'], ["widget282multi_company\tdept_index\tw282mco-001\tops"]]

## multi_index: one object in two different scope INSTANCES cleans up both
# Guards against the 4-tuple collapsing scope_id: each (scope instance,
# bucket) pair is its own entry.
@multi_co_b = Widget282MultiCompany.create!(company_id: 'w282mco-002')
@two_scope_emp = Widget282MultiEmployee.create!(emp_id: 'w282memp-004', department: 'qa')
@two_scope_emp.add_to_widget282multi_company_dept_index(@multi_co)
@two_scope_emp.add_to_widget282multi_company_dept_index(@multi_co_b)
@two_scope_before = [@multi_co.dept_index_for('qa').members, @multi_co_b.dept_index_for('qa').members]
@two_scope_emp.destroy!
[@two_scope_before,
 @multi_co.dept_index_for('qa').members,
 @multi_co_b.dept_index_for('qa').members]
#=> [[['w282memp-004'], ['w282memp-004']], [], []]

## A tab in the FIELD VALUE is allowed and round-trips
# Unlike the scope identifier, the value is the FINAL component of a
# tracker entry, so the limit-4 split leaves it intact however many tabs it
# holds -- and removal takes the bucket from the stored HSET value rather
# than re-parsing the key, so it cannot misdirect a delete.
@tabval_co = Widget282MultiCompany.create!(company_id: 'w282mco-tabval')
@tabval_emp = Widget282MultiEmployee.create!(emp_id: 'w282memp-tabval', department: "eng\tops")
@tabval_emp.add_to_widget282multi_company_dept_index(@tabval_co)
@tabval_before = @tabval_co.dept_index_for("eng\tops").members
@tabval_emp.destroy!
[@tabval_before, @tabval_co.dept_index_for("eng\tops").members]
#=> [['w282memp-tabval'], []]

## multi_index: two scope instances AND a value change all clean up
# The full cross product: 2 scope instances x 2 buckets = 4 tracker entries,
# every one of them removed by destroy!.
@x_emp = Widget282MultiEmployee.create!(emp_id: 'w282memp-005', department: 'before')
@x_emp.add_to_widget282multi_company_dept_index(@multi_co)
@x_emp.add_to_widget282multi_company_dept_index(@multi_co_b)
@x_emp.department = 'after'
@x_emp.save
@x_entry_count = @x_emp.send(:_index_scope_tracker).hgetall.size
@x_emp.destroy!
[@x_entry_count,
 @multi_co.dept_index_for('before').members, @multi_co.dept_index_for('after').members,
 @multi_co_b.dept_index_for('before').members, @multi_co_b.dept_index_for('after').members]
#=> [4, [], [], [], []]

## Reused identifier: multi_index buckets are pruned too (#365)
# Every bucket the dead incarnation occupied is cleared on the new
# record's save, exactly as destroy! would have cleared them, and the new
# record joins none of them.
@mre_co = Widget282MultiCompany.create!(company_id: 'w282mco-reuse')
@mre_a = Widget282MultiEmployee.create!(emp_id: 'w282memp-reuse', department: 'eng')
@mre_a.add_to_widget282multi_company_dept_index(@mre_co)
@mre_a.department = 'ops'
@mre_a.save
@mre_a.delete!
@mre_b = Widget282MultiEmployee.new(emp_id: 'w282memp-reuse', department: 'qa')
@mre_b.save
[@mre_co.dept_index_for('eng').members,
 @mre_co.dept_index_for('ops').members,
 @mre_co.dept_index_for('qa').members,
 @mre_b.send(:_index_scope_tracker).hgetall]
#=> [[], [], [], {}]

## Two scope classes sharing an index name each clean up their own entry
# The tracker records the scope config alongside the index name. Matching
# on index name alone always resolved to the first-declared relationship,
# so cleanup built a stub of the wrong class and mutated the wrong key.
class ::Widget282ScopeA < Familia::Horreum
  feature :relationships
  identifier_field :a_id
  field :a_id
end

class ::Widget282ScopeB < Familia::Horreum
  feature :relationships
  identifier_field :b_id
  field :b_id
end

class ::Widget282SharedName < Familia::Horreum
  feature :relationships
  identifier_field :doc_id
  field :doc_id
  field :slug

  # Same index_name, two different scope classes.
  unique_index :slug, :slug_index, within: Widget282ScopeA
  unique_index :slug, :slug_index, within: Widget282ScopeB
end

@shared_a = Widget282ScopeA.create!(a_id: 'w282a-001')
@shared_b = Widget282ScopeB.create!(b_id: 'w282b-001')
@shared_doc_a = Widget282SharedName.create!(doc_id: 'w282doc-a', slug: 'shared-slug')
@shared_doc_b = Widget282SharedName.create!(doc_id: 'w282doc-b', slug: 'shared-slug')
@shared_doc_a.add_to_widget282scope_a_slug_index(@shared_a)
@shared_doc_b.add_to_widget282scope_b_slug_index(@shared_b)
[@shared_a.slug_index.get('shared-slug'), @shared_b.slug_index.get('shared-slug')]
#=> ['w282doc-a', 'w282doc-b']

## Destroying the ScopeA-indexed doc leaves the ScopeB entry untouched
@shared_doc_a.destroy!
[@shared_a.slug_index.has_key?('shared-slug'), @shared_b.slug_index.get('shared-slug')]
#=> [false, 'w282doc-b']

## Destroying the ScopeB-indexed doc then clears the remaining entry
@shared_doc_b.destroy!
[@shared_a.slug_index.has_key?('shared-slug'), @shared_b.slug_index.has_key?('shared-slug')]
#=> [false, false]

## add_to_* raises when the scope instance has no identifier
# A blank scope identifier yields an ambiguous tracker entry and a
# malformed index key. Raising beats a silent skip: the alternative is an
# index entry nothing can ever clean up.
@blank_co = Widget241ScopedCompany.new
@blank_emp = Widget241ScopedEmployee.create!(emp_id: 'w241emp-blank', badge: 'B-BLANK')
@keys_before_blank = Familia.dbclient.keys('*').sort
begin
  @blank_emp.add_to_widget241scoped_company_badge_index(@blank_co)
  :no_raise
rescue Familia::NoIdentifier
  :no_identifier
end
#=> :no_identifier

## add_to_* with a blank scope identifier writes nothing
# The guard runs before the index write, so no partial state is left --
# neither a malformed index key nor a tracker entry to chase later.
[Familia.dbclient.keys('*').sort == @keys_before_blank,
 @blank_emp.send(:_index_scope_tracker).hgetall]
#=> [true, {}]

## update_in_* raises on a blank scope identifier too
begin
  @blank_emp.update_in_widget241scoped_company_badge_index(@blank_co, nil)
  :no_raise
rescue Familia::NoIdentifier
  :no_identifier
end
#=> :no_identifier

## Scope classes without a simple identifier field are rejected up front
# Cleanup runs inside destroy!'s MULTI and must rebuild the scope from its
# identifier alone -- no reads available. A Proc identifier_field cannot
# support that, so the index write is refused rather than tracked into a
# state destroy! could not undo.
class ::Widget282ProcScope < Familia::Horreum
  feature :relationships
  identifier_field ->(obj) { obj.scope_id }
  field :scope_id
end

class ::Widget282ProcScoped < Familia::Horreum
  feature :relationships
  identifier_field :thing_id
  field :thing_id
  field :label

  unique_index :label, :label_index, within: Widget282ProcScope
end

@proc_scope = Widget282ProcScope.new(scope_id: 'w282proc-001')
@proc_thing = Widget282ProcScoped.create!(thing_id: 'w282thing-001', label: 'L-1')
begin
  @proc_thing.add_to_widget282proc_scope_label_index(@proc_scope)
  :no_raise
rescue ArgumentError => e
  e.message.include?('simple (Symbol or String) identifier field')
end
#=> true

# Teardown: flush the database and remove throwaway constants so this
# tryout doesn't pollute sibling suites (index keys in particular can
# otherwise interfere with re-run iterations).
Familia.dbclient.flushdb
%i[
  Widget241
  Widget241ScopedEmployee
  Widget241ScopedCompany
  Widget282MultiEmployee
  Widget282MultiCompany
  Widget282SharedName
  Widget282ScopeA
  Widget282ScopeB
  Widget282ProcScoped
  Widget282ProcScope
  DwModeModel
].each do |const|
  Object.send(:remove_const, const) if Object.const_defined?(const)
end
