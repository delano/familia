# try/features/dirty_write_new_object_try.rb
#
# frozen_string_literal: true

# Tests for issue #278: detect a "new, unsaved object" as a distinct case in
# the dirty-write warnings emitted by Familia::DataType#warn_if_dirty!.
#
# A parent Horreum that has never been persisted (no hash key in Redis yet) is
# strictly more dangerous than a previously-saved parent with uncommitted
# scalar changes: mutating a collection orphans the collection data with no
# parent hash to anchor it. The warning system must distinguish the two.

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

## A freshly built, never-dirtied parent emits no warning at all
@clean = DirtyWriteWidget.new(widget_id: 'dww_clean', name: 'Clean')
@clean_output = capture_familia_warnings { @clean.tags.add('alpha') }
@clean_output.include?('Writing to')
#=> false

## New, unsaved + dirty parent: warning flags it as a new, unsaved object
@new_widget = DirtyWriteWidget.new(widget_id: 'dww_new', name: 'Original')
@new_widget.name = 'Changed'   # mutate AFTER construction -> dirty
@new_output = capture_familia_warnings { @new_widget.tags.add('beta') }
@new_output.include?('new, unsaved object')
#=> true

## The new-object warning still names the dirty scalar fields
@new_output.include?('unsaved scalar fields: name')
#=> true

## The new-object warning points at the orphaned-data hazard
@new_output.include?('orphaned data')
#=> true

## Saved-but-dirty parent: warning uses the milder, standard message
@saved_widget = DirtyWriteWidget.new(widget_id: 'dww_saved', name: 'Original')
@saved_widget.save
@saved_widget.name = 'Changed'  # dirty again, but parent hash now exists
@saved_output = capture_familia_warnings { @saved_widget.tags.add('gamma') }
@saved_output.include?('unsaved scalar fields: name')
#=> true

## Saved-but-dirty parent is NOT labelled a new, unsaved object
@saved_output.include?('new, unsaved object')
#=> false

## Under strict_write_order, a new, unsaved parent raises with the new-object message
@strict_new = DirtyWriteWidget.new(widget_id: 'dww_strict_new', name: 'Original')
@strict_new.name = 'Changed'
Familia.strict_write_order = true
begin
  @strict_new.tags.add('delta')
  @strict_new_outcome = [:no_raise]
rescue Familia::Problem => e
  @strict_new_outcome = [:raised, e.message.include?('new, unsaved object'),
                         e.message.include?('name')]
ensure
  Familia.strict_write_order = false
  @strict_new.clear_dirty!
end
@strict_new_outcome
#=> [:raised, true, true]

## Under strict_write_order, a saved-but-dirty parent raises with the standard message
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

## Once the new object is saved, later dirty writes drop the new-object label
@promote = DirtyWriteWidget.new(widget_id: 'dww_promote', name: 'Original')
@promote.name = 'BeforeSave'
@before_save_output = capture_familia_warnings { @promote.tags.add('one') }
@promote.save
@promote.name = 'AfterSave'
@after_save_output = capture_familia_warnings { @promote.tags.add('two') }
[@before_save_output.include?('new, unsaved object'),
 @after_save_output.include?('new, unsaved object')]
#=> [true, false]

## A collection write inside a transaction queues no extra EXISTS probe,
## even when the parent is a dirty new object. parent_new_record? short-circuits
## inside a MULTI, so the dirty path must queue exactly the same commands as the
## clean path (which never reaches the probe because it is not dirty).
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

# Teardown: remove the keys created above
DirtyWriteWidget.new(widget_id: 'dww_clean').tags.delete! rescue nil
DirtyWriteWidget.new(widget_id: 'dww_new').tags.delete! rescue nil
[
  'dww_saved', 'dww_strict_new', 'dww_strict_saved', 'dww_promote',
  'dww_txn_clean', 'dww_txn_dirty'
].each do |wid|
  w = DirtyWriteWidget.new(widget_id: wid)
  w.tags.delete! rescue nil
  w.destroy! rescue nil
end
