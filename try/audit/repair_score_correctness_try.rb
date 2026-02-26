# try/audit/repair_score_correctness_try.rb
#
# Tests that repair_instances! assigns correct scores using
# extract_timestamp_score's fallback cascade: updated -> created -> Familia.now
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Model with both updated and created fields
class ScoreBothModel < Familia::Horreum
  identifier_field :sid
  field :sid
  field :name
  field :updated
  field :created
end

# Model with only created (no updated field)
class ScoreCreatedOnlyModel < Familia::Horreum
  identifier_field :sid
  field :sid
  field :name
  field :created
end

# Model with neither updated nor created fields
class ScoreNoTimestampModel < Familia::Horreum
  identifier_field :sid
  field :sid
  field :name
end

# Clean up
begin
  %w[score_both_model score_created_only_model score_no_timestamp_model].each do |prefix|
    existing = Familia.dbclient.keys("#{prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
  end
rescue => e
  # Ignore cleanup errors
end
ScoreBothModel.instances.clear
ScoreCreatedOnlyModel.instances.clear
ScoreNoTimestampModel.instances.clear

## Create object with both timestamps, save, then overwrite updated via HSET
@known_updated = 1700000000.0
@s1 = ScoreBothModel.new(sid: 'sc-1', name: 'With Updated')
@s1.save
Familia.dbclient.hset(@s1.dbkey, 'updated', '1700000000.0')
Familia.dbclient.hset(@s1.dbkey, 'created', '1690000000.0')
ScoreBothModel.instances.member?('sc-1')
#=> true

## Remove from instances to simulate missing entry
ScoreBothModel.instances.remove('sc-1')
ScoreBothModel.instances.member?('sc-1')
#=> false

## repair_instances! adds the missing entry back
@result = ScoreBothModel.repair_instances!
@result[:missing_added]
#=> 1

## Score uses updated timestamp when both updated and created are present
ScoreBothModel.instances.score('sc-1')
#=> @known_updated

## Verify loaded object has the correct updated value
@loaded = ScoreBothModel.load('sc-1')
@loaded.updated
#=> @known_updated

## Create object with only created field, overwrite created via HSET
@known_created = 1680000000.0
@s2 = ScoreCreatedOnlyModel.new(sid: 'sc-2', name: 'Created Only')
@s2.save
Familia.dbclient.hset(@s2.dbkey, 'created', '1680000000.0')
ScoreCreatedOnlyModel.instances.remove('sc-2')
ScoreCreatedOnlyModel.instances.member?('sc-2')
#=> false

## repair_instances! adds the missing entry
@result = ScoreCreatedOnlyModel.repair_instances!
@result[:missing_added]
#=> 1

## Score uses created timestamp when model has no updated field
ScoreCreatedOnlyModel.instances.score('sc-2')
#=> @known_created

## ScoreCreatedOnlyModel does not respond to updated
ScoreCreatedOnlyModel.new(sid: 'tmp').respond_to?(:updated)
#=> false

## Create object with no timestamp fields
@before_repair = Familia.now
@s3 = ScoreNoTimestampModel.new(sid: 'sc-3', name: 'No Timestamps')
@s3.save
ScoreNoTimestampModel.instances.remove('sc-3')
ScoreNoTimestampModel.instances.member?('sc-3')
#=> false

## repair_instances! adds the missing entry
@result = ScoreNoTimestampModel.repair_instances!
@result[:missing_added]
#=> 1

## Score falls back to approximately Familia.now when no timestamp fields
@score = ScoreNoTimestampModel.instances.score('sc-3')
@after_repair = Familia.now
@score >= @before_repair && @score <= @after_repair
#=> true

## ScoreNoTimestampModel does not respond to updated or created
@tmp = ScoreNoTimestampModel.new(sid: 'tmp2')
[@tmp.respond_to?(:updated), @tmp.respond_to?(:created)]
#=> [false, false]

## After all repairs, each model's audit shows clean state
@a1 = ScoreBothModel.audit_instances
@a2 = ScoreCreatedOnlyModel.audit_instances
@a3 = ScoreNoTimestampModel.audit_instances
[@a1, @a2, @a3].all? { |a| a[:phantoms].empty? && a[:missing].empty? }
#=> true

# Teardown
begin
  %w[score_both_model score_created_only_model score_no_timestamp_model].each do |prefix|
    existing = Familia.dbclient.keys("#{prefix}:*")
    Familia.dbclient.del(*existing) if existing.any?
  end
rescue => e
  # Ignore cleanup errors
end
ScoreBothModel.instances.clear
ScoreCreatedOnlyModel.instances.clear
ScoreNoTimestampModel.instances.clear
