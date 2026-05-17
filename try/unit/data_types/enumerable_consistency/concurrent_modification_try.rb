# try/unit/data_types/enumerable_consistency/concurrent_modification_try.rb
#
# frozen_string_literal: true

# Tests SCAN-based iteration behavior under concurrent modification.
# SCAN provides weak consistency: may or may not see items added/removed during iteration,
# but guarantees completion without errors and sees all items present before iteration started
# that remain throughout.

require_relative '../../../support/helpers/test_helpers'

# Setup: Create test set
@bone = Bone.new 'concurrent_modification_test'

# ============================================================
# SCAN resilience to concurrent additions
# ============================================================

## SCAN-based iteration completes when items are added during iteration
# Add initial items
50.times { |i| @bone.tags.add "initial_#{i.to_s.rjust(2, '0')}" }
seen = []
@bone.tags.each(batch_size: 10) do |item|
  seen << item
  @bone.tags.add "added_during_#{seen.size}" if seen.size == 25
end
# Iteration completes without error
seen.size >= 50
#=> true

## SCAN sees all items present before iteration started
@bone2 = Bone.new 'concurrent_add_coverage_test'
50.times { |i| @bone2.tags.add "item_#{i.to_s.rjust(2, '0')}" }
original_items = @bone2.tags.members.dup
seen = []
@bone2.tags.each(batch_size: 10) do |item|
  seen << item
  @bone2.tags.add "new_#{seen.size}" if seen.size == 15
end
# All original items should be seen (SCAN guarantees items present throughout are visited)
(original_items - seen).empty?
#=> true

# ============================================================
# SCAN resilience to concurrent deletions
# ============================================================

## SCAN-based iteration handles concurrent deletions gracefully
@bone3 = Bone.new 'concurrent_delete_test'
50.times { |i| @bone3.tags.add "item_#{i.to_s.rjust(2, '0')}" }
seen = []
@bone3.tags.each(batch_size: 10) do |item|
  seen << item
  @bone3.tags.remove('item_49') if seen.size == 5
end
# Iteration completes without error (may or may not include deleted item)
seen.size >= 49
#=> true

## SCAN iteration completes even with many deletions
@bone4 = Bone.new 'concurrent_multi_delete_test'
100.times { |i| @bone4.tags.add "item_#{i.to_s.rjust(3, '0')}" }
seen = []
deleted = []
@bone4.tags.each(batch_size: 20) do |item|
  seen << item
  # Delete every 10th item we see
  if seen.size % 10 == 0 && seen.size < 80
    target = "item_#{(seen.size + 5).to_s.rjust(3, '0')}"
    @bone4.tags.remove(target)
    deleted << target
  end
end
# Iteration completes (deleted items may or may not be seen)
seen.size >= 92
#=> true

# ============================================================
# SCAN with mixed add/delete operations
# ============================================================

## SCAN handles mixed add and delete during iteration
@bone5 = Bone.new 'concurrent_mixed_ops_test'
30.times { |i| @bone5.tags.add "stable_#{i.to_s.rjust(2, '0')}" }
seen = []
@bone5.tags.each(batch_size: 5) do |item|
  seen << item
  case seen.size
  when 10
    @bone5.tags.add 'dynamic_added_1'
    @bone5.tags.add 'dynamic_added_2'
  when 20
    @bone5.tags.remove('stable_29')
  end
end
# All stable items (except possibly deleted one) should be seen
stable_seen = seen.select { |s| s.start_with?('stable_') && s != 'stable_29' }
stable_seen.size >= 29
#=> true

# ============================================================
# Sorted set concurrent modification
# ============================================================

## SortedSet ZSCAN handles concurrent additions
@bone6 = Bone.new 'zscan_concurrent_add_test'
50.times { |i| @bone6.metrics.add "metric_#{i.to_s.rjust(2, '0')}", i * 10.0 }
seen = []
@bone6.metrics.each(batch_size: 10) do |item|
  seen << item
  @bone6.metrics.add("added_metric_#{seen.size}", 999.0) if seen.size == 25
end
seen.size >= 50
#=> true

## SortedSet ZSCAN handles concurrent deletions
@bone7 = Bone.new 'zscan_concurrent_delete_test'
50.times { |i| @bone7.metrics.add "metric_#{i.to_s.rjust(2, '0')}", i * 10.0 }
seen = []
@bone7.metrics.each(batch_size: 10) do |item|
  seen << item
  @bone7.metrics.remove('metric_49') if seen.size == 5
end
seen.size >= 49
#=> true

# ============================================================
# HashKey concurrent modification
# ============================================================

## HashKey HSCAN handles concurrent additions
@bone8 = Bone.new 'hscan_concurrent_add_test'
50.times { |i| @bone8.props["key_#{i.to_s.rjust(2, '0')}"] = "value_#{i}" }
seen = []
@bone8.props.each(batch_size: 10) do |key, _value|
  seen << key
  @bone8.props["added_key_#{seen.size}"] = 'added_value' if seen.size == 25
end
seen.size >= 50
#=> true

## HashKey HSCAN handles concurrent deletions
@bone9 = Bone.new 'hscan_concurrent_delete_test'
50.times { |i| @bone9.props["key_#{i.to_s.rjust(2, '0')}"] = "value_#{i}" }
seen = []
@bone9.props.each(batch_size: 10) do |key, _value|
  seen << key
  @bone9.props.remove_field('key_49') if seen.size == 5
end
seen.size >= 49
#=> true

# ============================================================
# ListKey concurrent modification (non-cursor based)
# ============================================================

## ListKey handles concurrent additions
@bone10 = Bone.new 'list_concurrent_add_test'
30.times { |i| @bone10.owners.push "owner_#{i.to_s.rjust(2, '0')}" }
seen = []
@bone10.owners.each(batch_size: 10) do |item|
  seen << item
  @bone10.owners.push("added_owner_#{seen.size}") if seen.size == 15
end
# List iteration may see added items depending on timing
seen.size >= 30
#=> true

# Teardown: Clean up test data
[@bone, @bone2, @bone3, @bone4, @bone5, @bone6, @bone7, @bone8, @bone9, @bone10].each do |b|
  next unless b
  b.tags.clear rescue nil
  b.metrics.clear rescue nil
  b.props.clear rescue nil
  b.owners.clear rescue nil
end
