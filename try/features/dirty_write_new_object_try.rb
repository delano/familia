# try/features/dirty_write_new_object_try.rb
#
# frozen_string_literal: true

# Tests for issue #278: detect a "new, unsaved object" as a distinct case in
# the dirty-write warnings emitted by Familia::DataType#warn_if_dirty!.
#
# A parent Horreum that has never been persisted (no hash key in Redis yet) is
# strictly more dangerous than a previously-saved parent with uncommitted
# scalar changes: mutating a collection orphans the collection data with no
# parent hash to anchor it. The warning system must distinguish the two, and a
# new, unsaved parent RAISES by default (regardless of strict_write_order). The
# Familia.raise_on_unsaved_parent_write setting downgrades that to a warning.

require_relative '../support/helpers/test_helpers'
require 'stringio'

class DirtyWriteWidget < Familia::Horreum
  identifier_field :widget_id
  field :widget_id
  field :name
  list  :events
  set   :tags
end

# Capture everything Familia.warn emits during the block and return it as a
# String. Swaps the logger directly because Familia.logger is memoized and
# binds to its IO at first reference (reassigning $stderr would not work).
def capture_familia_warnings
  buffer = StringIO.new
  original = Familia.logger
  Familia.logger = Familia::FamiliaLogger.new(buffer)
  begin
    yield
  ensure
    Familia.logger = original
  end
  buffer.string
end

## The new setting defaults to true (raise)
Familia.raise_on_unsaved_parent_write
#=> true

## A freshly built, never-dirtied parent emits no warning and does not raise
@clean = DirtyWriteWidget.new(widget_id: 'dww_clean', name: 'Clean')
@clean_output = capture_familia_warnings { @clean.tags.add('alpha') }
@clean_output.include?('Writing to')
#=> false

## New, unsaved + dirty parent RAISES by default, with the distinct new-object message
@new_widget = DirtyWriteWidget.new(widget_id: 'dww_new', name: 'Original')
@new_widget.name = 'Changed'   # mutate AFTER construction -> dirty
@new_outcome =
  begin
    @new_widget.tags.add('beta')
    [:no_raise]
  rescue Familia::Problem => e
    [:raised, e.message.include?('new, unsaved object'),
     e.message.include?('unsaved scalar fields: name'),
     e.message.include?('orphaned data')]
  ensure
    @new_widget.clear_dirty!
  end
@new_outcome
#=> [:raised, true, true, true]

## The raise prevents the collection write, so no orphaned data is left behind
@new_widget.tags.members.empty?
#=> true

## raise_on_unsaved_parent_write=false downgrades the new-object case to a warning
@warn_widget = DirtyWriteWidget.new(widget_id: 'dww_warn', name: 'Original')
@warn_widget.name = 'Changed'
Familia.raise_on_unsaved_parent_write = false
@warn_output =
  begin
    capture_familia_warnings { @warn_widget.tags.add('gamma') }
  ensure
    Familia.raise_on_unsaved_parent_write = true
    @warn_widget.clear_dirty!
  end
[@warn_output.include?('new, unsaved object'), @warn_output.include?('orphaned data')]
#=> [true, true]

## With the downgrade, the collection write actually goes through (only warned)
@warn_widget.tags.members
#=> ['gamma']

## Saved-but-dirty parent only WARNS (no raise) and uses the milder message
@saved_widget = DirtyWriteWidget.new(widget_id: 'dww_saved', name: 'Original')
@saved_widget.save
@saved_widget.name = 'Changed'  # dirty again, but parent hash now exists
@saved_output =
  begin
    capture_familia_warnings { @saved_widget.tags.add('delta') }
  ensure
    @saved_widget.clear_dirty!
  end
[@saved_output.include?('unsaved scalar fields: name'),
 @saved_output.include?('new, unsaved object')]
#=> [true, false]

## Under strict_write_order, a saved-but-dirty parent raises the standard message
@strict_saved = DirtyWriteWidget.new(widget_id: 'dww_strict_saved', name: 'Original')
@strict_saved.save
@strict_saved.name = 'Changed'
Familia.strict_write_order = true
begin
  @strict_saved.tags.add('epsilon')
  @strict_saved_outcome = [:no_raise]
rescue Familia::Problem => e
  @strict_saved_outcome = [:raised, e.message.include?('new, unsaved object'),
                           e.message.include?('unsaved scalar fields')]
ensure
  Familia.strict_write_order = false
  @strict_saved.clear_dirty!
end
@strict_saved_outcome
#=> [:raised, false, true]

## strict_write_order overrides raise_on_unsaved_parent_write=false (still raises)
@override = DirtyWriteWidget.new(widget_id: 'dww_override', name: 'Original')
@override.name = 'Changed'
Familia.raise_on_unsaved_parent_write = false
Familia.strict_write_order = true
begin
  @override.tags.add('zeta')
  @override_outcome = [:no_raise]
rescue Familia::Problem => e
  @override_outcome = [:raised, e.message.include?('new, unsaved object')]
ensure
  Familia.strict_write_order = false
  Familia.raise_on_unsaved_parent_write = true
  @override.clear_dirty!
end
@override_outcome
#=> [:raised, true]

## Once the parent is saved, later dirty writes drop the new-object label and only warn
@promote = DirtyWriteWidget.new(widget_id: 'dww_promote', name: 'Original')
@promote.save
@promote.name = 'AfterSave'
@after_save_output =
  begin
    capture_familia_warnings { @promote.tags.add('two') }
  ensure
    @promote.clear_dirty!
  end
@after_save_output.include?('new, unsaved object')
#=> false

## A collection write inside a transaction queues no extra EXISTS probe and does
## not raise: parent_new_record? short-circuits in a MULTI, so a dirty new parent
## is treated as dirty-after-save (warn) and queues exactly the clean-path commands.
@txn_clean = DirtyWriteWidget.new(widget_id: 'dww_txn_clean', name: 'Clean')
@txn_clean_result = @txn_clean.transaction { |_c| @txn_clean.tags.add('v') }

@txn_dirty = DirtyWriteWidget.new(widget_id: 'dww_txn_dirty', name: 'Original')
@txn_dirty.name = 'Changed'   # dirty AND never saved
@txn_dirty_result =
  begin
    @txn_dirty.transaction { |_c| @txn_dirty.tags.add('v') }
  ensure
    @txn_dirty.clear_dirty!
  end
[@txn_dirty_result.successful?,
 @txn_dirty_result.results.size == @txn_clean_result.results.size]
#=> [true, true]

# Teardown: restore defaults and remove the keys created above
Familia.strict_write_order = false
Familia.raise_on_unsaved_parent_write = true
[
  'dww_clean', 'dww_new', 'dww_warn', 'dww_saved', 'dww_strict_saved',
  'dww_override', 'dww_promote', 'dww_txn_clean', 'dww_txn_dirty'
].each do |wid|
  w = DirtyWriteWidget.new(widget_id: wid)
  w.tags.delete! rescue nil
  w.destroy! rescue nil
end
