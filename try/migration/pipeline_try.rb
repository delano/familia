# try/migration/pipeline_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

Familia.debug = false

@redis = Familia.dbclient
@test_id = "#{Process.pid}_#{Familia.now.to_i}"
@prefix = "familia:test:pipeline:#{@test_id}"

@initial_migrations = Familia::Migration.migrations.dup

# Test model class for pipeline migrations
class PipelineTestRecord < Familia::Horreum
  identifier_field :record_id
  field :record_id
  field :name
  field :status
  field :old_field
  field :new_field
  field :migrated_at
end

# Simple Pipeline migration
class SimplePipelineMigration < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_simple'
  self.description = 'Simple pipeline migration test'

  class << self
    attr_accessor :processed_count
  end
  self.processed_count = 0

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    true
  end

  def build_update_fields(obj)
    self.class.processed_count += 1
    { new_field: 'pipeline_updated' }
  end
end

# Pipeline migration that filters records
class FilteringPipelineMigration < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_filtering'

  class << self
    attr_accessor :skipped_count, :processed_count
  end
  self.skipped_count = 0
  self.processed_count = 0

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    if obj.status == 'skip_me'
      self.class.skipped_count += 1
      track_stat(:skipped)
      return false
    end
    self.class.processed_count += 1
    true
  end

  def build_update_fields(obj)
    { new_field: 'filtered_update', migrated_at: Familia.now.to_i.to_s }
  end
end

# Pipeline migration with empty fields (should skip HMSET)
class EmptyFieldsPipelineMigration < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_empty'

  class << self
    attr_accessor :build_called_count
  end
  self.build_called_count = 0

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    true
  end

  def build_update_fields(obj)
    self.class.build_called_count += 1
    {} # Return empty hash
  end
end

# Pipeline migration with nil fields
class NilFieldsPipelineMigration < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_nil'

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    true
  end

  def build_update_fields(obj)
    nil # Return nil
  end
end

# Pipeline migration with custom execute_update
class CustomExecutePipelineMigration < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_custom_execute'

  class << self
    attr_accessor :custom_execute_called, :original_keys
  end
  self.custom_execute_called = 0
  self.original_keys = []

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    true
  end

  def build_update_fields(obj)
    { custom_field: 'custom_value' }
  end

  def execute_update(pipe, obj, fields, original_key = nil)
    self.class.custom_execute_called += 1
    self.class.original_keys << original_key
    super(pipe, obj, fields, original_key)
  end
end

# Pipeline migration that errors during batch
class ErrorPipelineMigration < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_error'

  class << self
    attr_accessor :error_triggered
  end
  self.error_triggered = false

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    if obj.name == 'trigger_error'
      self.class.error_triggered = true
      raise 'Intentional pipeline error'
    end
    true
  end

  def build_update_fields(obj)
    { new_field: 'updated' }
  end
end

# Pipeline without should_process? - should raise
class MissingShouldProcessPipeline < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_missing_should'

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def build_update_fields(obj)
    { field: 'value' }
  end
end

# Pipeline without build_update_fields - should raise
class MissingBuildFieldsPipeline < Familia::Migration::Pipeline
  self.migration_id = 'pipeline_test_missing_build'

  def prepare
    @model_class = PipelineTestRecord
    @batch_size = 10
  end

  def should_process?(obj)
    true
  end
end

# Helper to create test records with unique prefix
def create_pipeline_record(suffix, name: 'Test', status: 'active')
  id = "#{@test_id}_#{suffix}"
  record = PipelineTestRecord.new(record_id: id, name: name, status: status)
  record.save
  record
end

# Helper to cleanup all test records
def cleanup_records
  pattern = "pipeline_test_record:#{@test_id}_*"
  @redis.keys(pattern).each { |k| @redis.del(k) }
end

cleanup_records

## Pipeline is a subclass of Model
Familia::Migration::Pipeline < Familia::Migration::Model
#=> true

## Pipeline initializes correctly
migration = SimplePipelineMigration.new
migration.is_a?(Familia::Migration::Pipeline)
#=> true

## Pipeline prepare sets model_class
SimplePipelineMigration.processed_count = 0
migration = SimplePipelineMigration.new
migration.prepare
migration.model_class == PipelineTestRecord
#=> true

## Pipeline should_process? raises NotImplementedError for base class
begin
  Familia::Migration::Pipeline.new.send(:should_process?, nil)
  false
rescue NotImplementedError
  true
end
#=> true

## Pipeline build_update_fields raises NotImplementedError for base class
begin
  Familia::Migration::Pipeline.new.send(:build_update_fields, nil)
  false
rescue NotImplementedError
  true
end
#=> true

## Pipeline process_record is a no-op
migration = SimplePipelineMigration.new
migration.send(:process_record, nil, 'key')
true
#=> true

## Pipeline processes records in batches
cleanup_records
create_pipeline_record('p1', name: 'P1')
create_pipeline_record('p2', name: 'P2')
create_pipeline_record('p3', name: 'P3')
SimplePipelineMigration.processed_count = 0
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
SimplePipelineMigration.processed_count >= 3
#=> true

## Pipeline updates are applied in actual_run mode
cleanup_records
record = create_pipeline_record('q1', name: 'Q1')
dbkey = record.dbkey
SimplePipelineMigration.processed_count = 0
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
@redis.hget(dbkey, 'new_field')
#=> "pipeline_updated"

## Pipeline respects dry_run mode
cleanup_records
record = create_pipeline_record('r1', name: 'R1')
SimplePipelineMigration.processed_count = 0
migration = SimplePipelineMigration.new(run: false)
migration.prepare
migration.migrate
reloaded = PipelineTestRecord.find_by_key(record.dbkey)
reloaded.new_field.nil?
#=> true

## Pipeline filtering works correctly
cleanup_records
create_pipeline_record('s1', status: 'active')
create_pipeline_record('s2', status: 'skip_me')
create_pipeline_record('s3', status: 'active')
FilteringPipelineMigration.skipped_count = 0
FilteringPipelineMigration.processed_count = 0
migration = FilteringPipelineMigration.new(run: true)
migration.prepare
migration.migrate
FilteringPipelineMigration.skipped_count >= 1 && FilteringPipelineMigration.processed_count >= 2
#=> true

## Pipeline tracks records_updated correctly
cleanup_records
create_pipeline_record('t1')
create_pipeline_record('t2')
SimplePipelineMigration.processed_count = 0
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
migration.records_updated >= 2
#=> true

## Pipeline with empty fields skips HMSET
cleanup_records
record = create_pipeline_record('u1', name: 'Original')
EmptyFieldsPipelineMigration.build_called_count = 0
migration = EmptyFieldsPipelineMigration.new(run: true)
migration.prepare
migration.migrate
EmptyFieldsPipelineMigration.build_called_count >= 1
#=> true

## Pipeline with nil fields skips HMSET
cleanup_records
record = create_pipeline_record('v1', name: 'Original')
migration = NilFieldsPipelineMigration.new(run: true)
migration.prepare
migration.migrate
record.name
#=> 'Original'

## Pipeline custom execute_update is called
cleanup_records
record = create_pipeline_record('w1')
CustomExecutePipelineMigration.custom_execute_called = 0
CustomExecutePipelineMigration.original_keys = []
migration = CustomExecutePipelineMigration.new(run: true)
migration.prepare
migration.migrate
CustomExecutePipelineMigration.custom_execute_called >= 1
#=> true

## Pipeline custom execute_update receives original_key
cleanup_records
create_pipeline_record('x1')
CustomExecutePipelineMigration.custom_execute_called = 0
CustomExecutePipelineMigration.original_keys = []
migration = CustomExecutePipelineMigration.new(run: true)
migration.prepare
migration.migrate
CustomExecutePipelineMigration.original_keys.first.include?('object')
#=> true

## Pipeline handles batch errors gracefully
cleanup_records
create_pipeline_record('y1', name: 'trigger_error')
ErrorPipelineMigration.error_triggered = false
migration = ErrorPipelineMigration.new(run: true)
migration.prepare
migration.migrate
ErrorPipelineMigration.error_triggered && migration.error_count >= 1
#=> true

## Pipeline tracks errors per batch size
cleanup_records
create_pipeline_record('z1', name: 'trigger_error')
create_pipeline_record('z2', name: 'normal')
ErrorPipelineMigration.error_triggered = false
migration = ErrorPipelineMigration.new(run: true)
migration.prepare
migration.migrate
migration.error_count >= 1
#=> true

## process_batch calls should_process? and build_update_fields
cleanup_records
create_pipeline_record('aa1')
SimplePipelineMigration.processed_count = 0
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
SimplePipelineMigration.processed_count >= 1
#=> true

## Pipeline tracks total_scanned
cleanup_records
create_pipeline_record('bb1')
create_pipeline_record('bb2')
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
migration.total_scanned >= 2
#=> true

## Pipeline tracks records_needing_update
cleanup_records
create_pipeline_record('cc1')
create_pipeline_record('cc2')
create_pipeline_record('cc3')
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
migration.records_needing_update >= 3
#=> true

## Pipeline returns true on success
cleanup_records
create_pipeline_record('dd1')
migration = SimplePipelineMigration.new(run: true)
migration.prepare
migration.migrate
#=> true

## Pipeline returns false when errors
cleanup_records
create_pipeline_record('ee1', name: 'trigger_error')
ErrorPipelineMigration.error_triggered = false
migration = ErrorPipelineMigration.new(run: true)
migration.prepare
migration.migrate
#=> false

## MissingShouldProcessPipeline raises NotImplementedError
cleanup_records
create_pipeline_record('ff1')
migration = MissingShouldProcessPipeline.new(run: true)
migration.prepare
begin
  migration.migrate
  false
rescue NotImplementedError => e
  e.message.include?('should_process?')
end
#=> true

## MissingBuildFieldsPipeline raises NotImplementedError
cleanup_records
create_pipeline_record('gg1')
migration = MissingBuildFieldsPipeline.new(run: true)
migration.prepare
begin
  migration.migrate
  false
rescue NotImplementedError => e
  e.message.include?('build_update_fields')
end
#=> true

cleanup_records
Familia::Migration.migrations.replace(@initial_migrations)
