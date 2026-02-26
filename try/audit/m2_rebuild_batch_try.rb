# try/audit/m2_rebuild_batch_try.rb
#
# frozen_string_literal: true

# M2: process_rebuild_batch correctness
#
# Verifies that rebuild_instances produces correct results after
# transaction batching was applied to process_rebuild_batch.

require_relative '../support/helpers/test_helpers'

class M2RebuildModel < Familia::Horreum
  identifier_field :m2id
  field :m2id
  field :name
  field :updated
  field :created
end

# Clean up
begin
  existing = Familia.dbclient.keys('m2_rebuild_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
M2RebuildModel.instances.clear

## Create test objects with known timestamps
@m1 = M2RebuildModel.new(m2id: 'm2-alpha', name: 'Alpha', updated: Familia.now.to_f)
@m1.save
@m2 = M2RebuildModel.new(m2id: 'm2-beta', name: 'Beta', updated: Familia.now.to_f)
@m2.save
@m3 = M2RebuildModel.new(m2id: 'm2-gamma', name: 'Gamma', updated: Familia.now.to_f)
@m3.save
@m4 = M2RebuildModel.new(m2id: 'm2-delta', name: 'Delta', updated: Familia.now.to_f)
@m4.save
@m5 = M2RebuildModel.new(m2id: 'm2-epsilon', name: 'Epsilon', updated: Familia.now.to_f)
@m5.save
M2RebuildModel.instances.size
#=> 5

## Clear timeline and rebuild; all 5 entries restored
M2RebuildModel.instances.clear
M2RebuildModel.rebuild_instances
#=> 5

## After rebuild, timeline has exactly 5 entries
M2RebuildModel.instances.size
#=> 5

## Each identifier is present after rebuild
['m2-alpha', 'm2-beta', 'm2-gamma', 'm2-delta', 'm2-epsilon'].all? { |id|
  M2RebuildModel.in_instances?(id)
}
#=> true

## Each identifier has a positive timestamp score
['m2-alpha', 'm2-beta', 'm2-gamma', 'm2-delta', 'm2-epsilon'].all? { |id|
  M2RebuildModel.instances.score(id).to_f > 0
}
#=> true

## Rebuild with small batch_size (forces multiple batches) produces same count
M2RebuildModel.instances.clear
M2RebuildModel.rebuild_instances(batch_size: 2)
#=> 5

## Small batch rebuild still has all identifiers
['m2-alpha', 'm2-beta', 'm2-gamma', 'm2-delta', 'm2-epsilon'].all? { |id|
  M2RebuildModel.in_instances?(id)
}
#=> true

## Rebuild with batch_size: 1 (one entry per batch) still works
M2RebuildModel.instances.clear
M2RebuildModel.rebuild_instances(batch_size: 1)
#=> 5

## Phantom entries are excluded after rebuild via atomic swap
M2RebuildModel.instances.add('phantom-m2', Familia.now)
M2RebuildModel.instances.size
#=> 6

## Rebuild eliminates the phantom
M2RebuildModel.rebuild_instances
#=> 5

## Phantom is gone from timeline
M2RebuildModel.in_instances?('phantom-m2')
#=> false

## Real entries survive the rebuild
M2RebuildModel.instances.size
#=> 5

## Rebuild is idempotent across repeated calls
@c1 = M2RebuildModel.rebuild_instances
@c2 = M2RebuildModel.rebuild_instances
@c1 == @c2
#=> true

# Teardown
begin
  existing = Familia.dbclient.keys('m2_rebuild_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
M2RebuildModel.instances.clear
