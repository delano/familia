# try/audit/rebuild_instances_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class RebuildModel < Familia::Horreum
  identifier_field :rbid
  field :rbid
  field :name
  field :updated
  field :created
end

# Clean up
begin
  existing = Familia.dbclient.keys('rebuild_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RebuildModel.instances.clear

## rebuild_instances exists as class method
RebuildModel.respond_to?(:rebuild_instances)
#=> true

## rebuild_instances on empty DB returns 0
RebuildModel.rebuild_instances
#=> 0

## Create objects for rebuild
@rb1 = RebuildModel.new(rbid: 'rb-1', name: 'Alpha')
@rb1.save
@rb2 = RebuildModel.new(rbid: 'rb-2', name: 'Beta')
@rb2.save
@rb3 = RebuildModel.new(rbid: 'rb-3', name: 'Gamma')
@rb3.save
RebuildModel.instances.size
#=> 3

## Clear instances and rebuild from SCAN
RebuildModel.instances.clear
RebuildModel.instances.size
#=> 0

## rebuild_instances returns count of rebuilt entries
count = RebuildModel.rebuild_instances
count
#=> 3

## After rebuild, all entries are in timeline
RebuildModel.instances.size
#=> 3

## After rebuild, specific identifiers are present
RebuildModel.in_instances?('rb-1')
#=> true

## All identifiers present after rebuild
RebuildModel.in_instances?('rb-2') && RebuildModel.in_instances?('rb-3')
#=> true

## rebuild_instances uses timestamp scores
score = RebuildModel.instances.score('rb-1')
score.to_f > 0
#=> true

## rebuild_instances accepts batch_size
RebuildModel.instances.clear
count = RebuildModel.rebuild_instances(batch_size: 1)
count
#=> 3

## rebuild_instances accepts progress callback
@progress = []
RebuildModel.instances.clear
RebuildModel.rebuild_instances { |p| @progress << p }
@progress.any? { |p| p[:phase] == :rebuilding }
#=> true

## Progress reports completed phase
@progress.any? { |p| p[:phase] == :completed }
#=> true

## Rebuild handles phantom entries (stale timeline, missing key)
RebuildModel.instances.add('phantom-id', Familia.now)
RebuildModel.instances.size
#=> 4

## Rebuild replaces phantoms via atomic swap
count = RebuildModel.rebuild_instances
count
#=> 3

## After rebuild, phantom is gone
RebuildModel.in_instances?('phantom-id')
#=> false

## After rebuild, real entries remain
RebuildModel.instances.size
#=> 3

## Rebuild is idempotent (multiple calls produce same result)
count1 = RebuildModel.rebuild_instances
count2 = RebuildModel.rebuild_instances
count1 == count2
#=> true

# Teardown
begin
  existing = Familia.dbclient.keys('rebuild_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RebuildModel.instances.clear
