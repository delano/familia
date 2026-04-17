# try/unit/horreum/unique_index_split_identifier_try.rb
#
# frozen_string_literal: true

#
# Split-identifier unique index corruption tests (issue #243)
#
# Exercises the forensic production case where the class-level unique_index
# HashKey maps `field_value -> ID-A`, but the actual object hash lives at
# `<ID-B>:object` AND the `instances` sorted set only contains ID-B. The
# index and the record disagree on the identifier for a single logical
# record.
#
# Verifies:
#   1. audit_unique_indexes surfaces the disagreement
#   2. rebuild_<name>_index repairs the mapping (foo -> ID-B)
#   3. guard_unique_<name>_index! raises RecordExistsError prior to rebuild
#   5. Multiple indexes on one class: corrupting one does not touch the other
#   6. Phantom + missing combined shapes
#   7. Dual disagreement (value_mismatch) and a known audit gap
#   8. Nil/empty field-value behavior (pinned)
#  10. Rebuild convergence invariant (instances -> index)
#  11. Rebuild does not resurrect phantoms (index values subset of instances)
#  12. Audit-rebuild-audit idempotence across corruption shapes
#
# Storage notes:
#   Where tests seed corruption, they use the public HashKey setter
#   (`Widget.name_index['foo'] = 'ID-A'`) rather than raw `dbclient.hset`.
#   This routes through `serialize_value` -- the same encoder used in
#   production by `add_to_class_<index>` (see
#   lib/familia/features/relationships/indexing/unique_index_generators.rb:418).
#   Keeping the test surface decoupled from the on-disk encoding means
#   future encoding changes will not silently bypass these tests.

require_relative '../../support/helpers/test_helpers'

class ::Widget < Familia::Horreum
  feature :relationships

  identifier_field :widget_id
  field :widget_id
  field :name

  unique_index :name, :name_index
end

class ::MultiIndexWidget < Familia::Horreum
  feature :relationships

  identifier_field :widget_id
  field :widget_id
  field :name
  field :email

  unique_index :name, :name_index
  unique_index :email, :email_index
end

class ::EmptyWidget < Familia::Horreum
  feature :relationships

  identifier_field :widget_id
  field :widget_id
  field :name

  unique_index :name, :name_index
end

# Reset all Widget state before seeding. The forensic corruption is injected
# by saving the real record first (which populates the index correctly) and
# then forcibly overwriting the index entry with a disagreeing identifier.
Widget.name_index.clear
Widget.instances.clear
MultiIndexWidget.name_index.clear
MultiIndexWidget.email_index.clear
MultiIndexWidget.instances.clear
EmptyWidget.name_index.clear
EmptyWidget.instances.clear

@real = Widget.new(widget_id: 'ID-B', name: 'foo')
@real.save
# Corrupt the index: overwrite foo -> ID-B with foo -> ID-A. ID-A is a
# purely phantom identifier; no object hash exists at widget:ID-A:object.
# Using HashKey#[]= routes through serialize_value (same path as
# add_to_class_<index>), so the test tracks any future encoding change.
Widget.name_index['foo'] = 'ID-A'

## Scenario 1a: audit returns an array with one entry for :name_index
@audit = Widget.audit_unique_indexes
@audit.size
#=> 1

## Scenario 1a: index_name is :name_index
@audit.first[:index_name]
#=> :name_index

## Scenario 1b: stale entry records field_value, reason, and phantom indexed_id
e = @audit.first[:stale].first
[e[:field_value], e[:reason], e[:indexed_id]]
#=> ["foo", :object_missing, "ID-A"]

## Scenario 1c: ID-B is not :missing because 'foo' is already an index key;
## the disagreement is surfaced through :object_missing on the phantom ID-A,
## which is sufficient for rebuild to reconverge.
@audit.first[:missing]
#=> []

## Scenario 2a: rebuild_name_index returns indexed count (Integer)
Widget.rebuild_name_index
#=:> Integer

## Scenario 2b: after rebuild, index maps foo -> ID-B (the real object)
Widget.name_index.get('foo')
#=> "ID-B"

## Scenario 2c: follow-up audit reports no stale or missing entries
@audit_after = Widget.audit_unique_indexes
[@audit_after.first[:stale], @audit_after.first[:missing]]
#=> [[], []]

## Scenario 3a: re-seed corruption for the guard test
Widget.name_index['foo'] = 'ID-A'
# Constructing a fresh instance representing ID-B and re-saving triggers
# the guard, which sees foo -> ID-A and identifier 'ID-B' disagreeing.
@duplicate = Widget.new(widget_id: 'ID-B', name: 'foo')
@duplicate.save
#=!> Familia::RecordExistsError

## Scenario 3b: error message carries class and field=value
begin
  Widget.new(widget_id: 'ID-B', name: 'foo').save
  nil
rescue Familia::RecordExistsError => e
  [e.message.include?('Widget'), e.message.include?('name=foo')]
end
#=> [true, true]

# Forward-compatibility note for issue #242 (still OPEN as of this tryout):
# Once RecordExistsError exposes an `existing_id` attribute, the following
# stanza should assert that it equals "ID-A" (the phantom ID in the index).
# Do NOT enable these expectations until #242 lands -- they will fail today
# because RecordExistsError only has `attr_reader :key`.
#
#   begin
#     Widget.new(widget_id: 'ID-B', name: 'foo').save
#   rescue Familia::RecordExistsError => e
#     e.existing_id  # expected: "ID-A"
#   end
#   #=> "ID-A"

## Scenario 5a: Multiple indexes on one class -- corrupt only name_index,
## verify rebuild of name_index does not disturb email_index. Audit
## reports stale on name_index after direct index overwrite.
@multi_real = MultiIndexWidget.new(widget_id: 'MW-1', name: 'alpha', email: 'alpha@test.com')
@multi_real.save
MultiIndexWidget.name_index['alpha'] = 'MW-PHANTOM'
@multi_audit = MultiIndexWidget.audit_unique_indexes
@multi_audit.find { |r| r[:index_name] == :name_index }[:stale].map { |e| e[:field_value] }
#=> ["alpha"]

## Scenario 5c: rebuild_name_index repairs only name_index
MultiIndexWidget.rebuild_name_index
MultiIndexWidget.name_index.get('alpha')
#=> "MW-1"

## Scenario 5d: email_index remains intact (not touched by name rebuild)
MultiIndexWidget.email_index.get('alpha@test.com')
#=> "MW-1"

## Scenario 5e: post-rebuild audit is fully clean across both indexes
@multi_audit_after = MultiIndexWidget.audit_unique_indexes
@multi_audit_after.all? { |r| r[:stale].empty? && r[:missing].empty? }
#=> true

## Scenario 6a: Phantom index entry combined with a real record whose
## field value is absent from the index. Here we test the complement of
## scenario 1: index has a phantom under a field value no real record
## uses, so the real record should appear under :missing while the
## phantom appears under :stale.
# Purge all prior Widget hash keys so the audit's SCAN is clean.
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
@real2 = Widget.new(widget_id: 'ID-REAL', name: 'bar')
@real2.save
Widget.name_index['ghost'] = 'ID-PHANTOM'
# Remove the legitimate 'bar' entry that save() populated, so ID-REAL is
# genuinely missing from the index.
Widget.name_index.remove_field('bar')
@audit6 = Widget.audit_unique_indexes
@audit6.first[:stale].map { |e| [e[:field_value], e[:reason]] }
#=> [["ghost", :object_missing]]

## Scenario 6b: audit shows missing for ID-REAL (field_value='bar')
@audit6.first[:missing].map { |m| [m[:identifier], m[:field_value]] }
#=> [["ID-REAL", "bar"]]

## Scenario 7a: Dual disagreement -- index claims foo -> ID-A but ID-A's
## real record has name='qux' (not foo), AND ID-B exists with name='foo'.
## This should surface as :value_mismatch for the foo entry.
# Purge all prior Widget hash keys so the audit's SCAN is clean.
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
@a = Widget.new(widget_id: 'ID-A', name: 'qux')
@a.save
@b = Widget.new(widget_id: 'ID-B', name: 'foo')
@b.save
# save() indexed qux->ID-A and foo->ID-B. Now swap the foo entry to point
# at ID-A (which actually has name='qux'), creating value_mismatch.
Widget.name_index['foo'] = 'ID-A'
@audit7 = Widget.audit_unique_indexes
@stale7 = @audit7.first[:stale].find { |e| e[:field_value] == 'foo' }
@stale7[:reason]
#=> :value_mismatch

## Scenario 7b: stale entry records current_value='qux'
@stale7[:current_value]
#=> "qux"

## Scenario 7c: KNOWN GAP -- when index entry is mapped to wrong identifier,
## the live record is NOT reported as :missing or in any conflict category.
## Audit's missing-scan uses `entries.keys.to_set` (value presence) rather
## than verifying the value-to-id mapping is correct from the record's
## perspective. Pinned as characterization; follow-up issue to be filed
## after this PR lands. See lib/familia/horreum/management/audit.rb:213-227.
@audit7.first[:missing].map { |m| m[:identifier] }.sort
#=> []

# Forward-compat (when audit gap is fixed):
# result = Widget.audit_unique_indexes
# result.first[:conflicts]
# #=> [{identifier: 'ID-B', field_value: 'foo', reason: :indexed_to_other, indexed_id: 'ID-A'}]

## Scenario 8: Nil field values are not indexed on save, and are correctly
## excluded from the missing-scan (mirroring write-path semantics).
EmptyWidget.name_index.clear
EmptyWidget.instances.clear
@nil_widget = EmptyWidget.new(widget_id: 'EW-NIL', name: nil)
@nil_widget.save
@audit8 = EmptyWidget.audit_unique_indexes
@audit8.first[:stale]
#=> []

## Scenario 8a: with name=nil, the object is not reported missing because
## the audit skips nil/empty field values when scanning for missing entries.
@audit8.first[:missing]
#=> []

## Scenario 8c: Empty-string indexed values ARE written to the index
## (add_to_class_<index> only short-circuits on nil; '' is truthy in Ruby
## and reaches the HSET), while the audit's missing-scan still skips '' via
## `value.to_s.strip.empty?` at lib/familia/horreum/management/audit.rb:222.
## Pinned behavior: index has {'' => 'EW-EMPTY'}, audit reports clean.
EmptyWidget.name_index.clear
EmptyWidget.instances.clear
@empty_widget = EmptyWidget.new(widget_id: 'EW-EMPTY', name: '')
@empty_widget.save
@audit8c = EmptyWidget.audit_unique_indexes
[EmptyWidget.name_index.hgetall, @audit8c.first[:stale], @audit8c.first[:missing]]
#=> [{"" => "EW-EMPTY"}, [], []]

## Scenario 10: Rebuild convergence invariant -- for every id in
## instances.members, name_index.get(record.name) == id. Seeds multiple
## records (one corrupted, others clean) so the `.all?` quantifier
## genuinely iterates and a regression affecting any single record would
## fail the invariant.
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
@s10_a = Widget.new(widget_id: 'S10-A', name: 'alpha')
@s10_a.save
@s10_b = Widget.new(widget_id: 'S10-B', name: 'beta')
@s10_b.save
@s10_c = Widget.new(widget_id: 'S10-C', name: 'gamma')
@s10_c.save
# Corrupt only 'alpha' -- point it at a phantom id. Other records remain clean.
Widget.name_index['alpha'] = 'S10-PHANTOM'
Widget.rebuild_name_index
Widget.instances.members.all? do |id|
  rec = Widget.find_by_id(id)
  rec && Widget.name_index.get(rec.name) == id
end
#=> true

## Scenario 11: Rebuild does not resurrect phantoms. After rebuild, every
## value in name_index.hgetall must be an id present in instances.members.
## Pins the contract: rebuild treats instances (+ scanned hashes) as source
## of truth and discards phantom index values.
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
@s11_real = Widget.new(widget_id: 'ID-B', name: 'foo')
@s11_real.save
Widget.name_index['foo'] = 'ID-A' # phantom id not in instances
Widget.name_index['zz'] = 'ID-Z'  # second phantom, different field value
Widget.rebuild_name_index
live_ids = Widget.instances.members.to_set
indexed_ids = Widget.name_index.hgetall.values.to_set
indexed_ids.subset?(live_ids)
#=> true

## Scenario 11b: Post-rebuild index is non-empty when live records exist.
## Guards against a silent regression that would empty the index (which
## would trivially satisfy the subset? check above).
Widget.name_index.hgetall.size
#=> 1

## Scenario 12a: Audit-rebuild-audit idempotence for split-identifier shape
## (index value points at phantom id; real record's value absent from index).
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
# Order matters (applies to 12a/12b/12c): save real record BEFORE injecting
# phantom so rebuild has an authoritative source in `instances` to converge on.
@s12a_real = Widget.new(widget_id: 'ID-B', name: 'foo')
@s12a_real.save
Widget.name_index['foo'] = 'ID-A'
Widget.rebuild_name_index
audit_after = Widget.audit_unique_indexes.first
[audit_after[:stale], audit_after[:missing]]
#=> [[], []]

## Scenario 12b: Audit-rebuild-audit idempotence for phantom+missing shape
## (phantom index entry under unused field value, real record missing from
## index entirely).
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
@s12b_real = Widget.new(widget_id: 'ID-REAL', name: 'bar')
@s12b_real.save
Widget.name_index['ghost'] = 'ID-PHANTOM'
Widget.name_index.remove_field('bar')
Widget.rebuild_name_index
audit_after = Widget.audit_unique_indexes.first
[audit_after[:stale], audit_after[:missing]]
#=> [[], []]

## Scenario 12c: Audit-rebuild-audit idempotence for value_mismatch shape
## (foo indexed to ID-A which actually has name='qux').
prior_keys = Widget.dbclient.keys('widget:*:object')
Widget.dbclient.del(*prior_keys) if prior_keys.any?
Widget.name_index.clear
Widget.instances.clear
@s12c_a = Widget.new(widget_id: 'ID-A', name: 'qux')
@s12c_a.save
@s12c_b = Widget.new(widget_id: 'ID-B', name: 'foo')
@s12c_b.save
Widget.name_index['foo'] = 'ID-A'
Widget.rebuild_name_index
audit_after = Widget.audit_unique_indexes.first
[audit_after[:stale], audit_after[:missing]]
#=> [[], []]

# Teardown -- @duplicate aliases @real's identifier 'ID-B' so @real.destroy!
# cleans both incidentally; the explicit list preserves the rest.
[
  @real, @real2, @a, @b, @multi_real,
  @nil_widget, @empty_widget,
  @s10_a, @s10_b, @s10_c, @s11_real,
  @s12a_real, @s12b_real, @s12c_a, @s12c_b
].each do |obj|
  obj.destroy! if obj.respond_to?(:destroy!) && obj.respond_to?(:exists?) && obj.exists?
end

Widget.name_index.clear
Widget.instances.clear
MultiIndexWidget.name_index.clear
MultiIndexWidget.email_index.clear
MultiIndexWidget.instances.clear
EmptyWidget.name_index.clear
EmptyWidget.instances.clear

# Clean up any lingering raw keys so the suite doesn't carry state.
begin
  %w[widget:* multi_index_widget:* empty_widget:*].each do |pattern|
    keys = Familia.dbclient.keys(pattern)
    Familia.dbclient.del(*keys) if keys.any?
  end
rescue StandardError
  # ignore cleanup errors
end
