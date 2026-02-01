# try/migration/model_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

Familia.debug = false

@redis = Familia.dbclient
@prefix = "familia:test:model:#{Process.pid}:#{Time.now.to_i}"

@initial_migrations = Familia::Migration.migrations.dup

# Test model class for migrations - a minimal Horreum with fields we can test
class ModelTestRecord < Familia::Horreum
  identifier_field :record_id
  field :record_id
  field :name
  field :status
  field :legacy_field
  field :new_field
end

# Simple Model migration for testing
class SimpleModelMigration < Familia::Migration::Model
  self.migration_id = 'model_test_simple'
  self.description = 'Simple model migration test'

  class << self
    attr_accessor :processed_keys
  end
  self.processed_keys = []

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def process_record(obj, key)
    self.class.processed_keys << key
    track_stat(:records_updated)
  end
end

# Model migration that skips records
class SkippingModelMigration < Familia::Migration::Model
  self.migration_id = 'model_test_skipping'

  class << self
    attr_accessor :skipped_count, :processed_count
  end
  self.skipped_count = 0
  self.processed_count = 0

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def process_record(obj, key)
    if obj.status == 'skip_me'
      self.class.skipped_count += 1
      track_stat(:skipped)
      return
    end

    for_realsies_this_time? do
      obj.new_field = 'migrated'
      obj.save
      self.class.processed_count += 1
    end
    track_stat(:records_updated)
  end
end

# Model migration that raises errors
class ErrorModelMigration < Familia::Migration::Model
  self.migration_id = 'model_test_error'

  class << self
    attr_accessor :error_triggered
  end
  self.error_triggered = false

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def process_record(obj, key)
    if obj.name == 'trigger_error'
      self.class.error_triggered = true
      raise 'Intentional test error'
    end
    track_stat(:records_updated)
  end
end

# Model migration without model_class - should fail validation
class InvalidModelMigration < Familia::Migration::Model
  self.migration_id = 'model_test_invalid'

  def prepare
    # Intentionally not setting @model_class
  end

  def process_record(obj, key)
    # Never called
  end
end

# Model migration with custom load_from_key
class CustomLoadMigration < Familia::Migration::Model
  self.migration_id = 'model_test_custom_load'

  class << self
    attr_accessor :custom_load_called
  end
  self.custom_load_called = false

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def load_from_key(key)
    self.class.custom_load_called = true
    super(key)
  end

  def process_record(obj, key)
    track_stat(:records_updated)
  end
end

# Model migration with custom scan pattern
class CustomPatternMigration < Familia::Migration::Model
  self.migration_id = 'model_test_pattern'

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
    @scan_pattern = "#{@prefix}:custom:*"
  end

  def process_record(obj, key)
    track_stat(:records_updated)
  end
end

# Model migration with validation hooks
class ValidatingModelMigration < Familia::Migration::Model
  self.migration_id = 'model_test_validation'

  class << self
    attr_accessor :before_validation_count, :after_validation_count
  end
  self.before_validation_count = 0
  self.after_validation_count = 0

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def validate_before_transform?
    true
  end

  def validate_after_transform?
    true
  end

  def process_record(obj, key)
    track_stat(:records_updated)
  end
end

# Model migration that returns migration_needed? false
class NotNeededMigration < Familia::Migration::Model
  self.migration_id = 'model_test_not_needed'

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def migration_needed?
    false
  end

  def process_record(obj, key)
    track_stat(:records_updated)
  end
end

# Model migration with track_stat_and_log_reason
class LoggingModelMigration < Familia::Migration::Model
  self.migration_id = 'model_test_logging'

  class << self
    attr_accessor :decisions_logged
  end
  self.decisions_logged = []

  def prepare
    @model_class = ModelTestRecord
    @batch_size = 10
  end

  def process_record(obj, key)
    track_stat_and_log_reason(obj, 'updated', 'name')
    track_stat(:records_updated)
  end
end

# Helper to create test records
def create_test_record(id, name: 'Test', status: 'active')
  record = ModelTestRecord.new(record_id: id, name: name, status: status)
  record.save
  record
end

# Helper to cleanup
def cleanup_records
  @redis.keys("modeltestrecord:*").each { |k| @redis.del(k) }
  @redis.keys("#{@prefix}:*").each { |k| @redis.del(k) }
end

cleanup_records

## Model class is a subclass of Base
Familia::Migration::Model < Familia::Migration::Base
#=> true

## Model initializes with default counters
migration = SimpleModelMigration.new
[migration.total_scanned, migration.records_needing_update,
 migration.records_updated, migration.error_count]
#=> [0, 0, 0, 0]

## Model initializes with default batch_size from config
migration = SimpleModelMigration.new
migration.batch_size == Familia::Migration.config.batch_size
#=> true

## Model prepare sets model_class
SimpleModelMigration.processed_keys = []
migration = SimpleModelMigration.new
migration.prepare
migration.model_class == ModelTestRecord
#=> true

## Model prepare allows custom batch_size
migration = SimpleModelMigration.new
migration.prepare
migration.batch_size
#=> 10

## Model validate raises when model_class not set
begin
  migration = InvalidModelMigration.new
  migration.prepare
  migration.migrate
  false
rescue Familia::Migration::Errors::PreconditionFailed => e
  e.message.include?('Model class not set')
end
#=> true

## Model validate raises for non-Horreum class
class NonHorreumMigration < Familia::Migration::Model
  self.migration_id = 'model_test_non_horreum'
  def prepare
    @model_class = String
  end
  def process_record(obj, key); end
end
begin
  migration = NonHorreumMigration.new
  migration.prepare
  migration.migrate
  false
rescue Familia::Migration::Errors::PreconditionFailed => e
  e.message.include?('must be a Familia::Horreum subclass')
end
#=> true

## Model migration processes records via SCAN
cleanup_records
create_test_record("#{@prefix}:record1", name: 'Record 1')
create_test_record("#{@prefix}:record2", name: 'Record 2')
SimpleModelMigration.processed_keys = []
migration = SimpleModelMigration.new(run: true)
migration.prepare
migration.migrate
SimpleModelMigration.processed_keys.size
#=> 2

## Model migration tracks total_scanned
cleanup_records
create_test_record("#{@prefix}:a1", name: 'A1')
create_test_record("#{@prefix}:a2", name: 'A2')
create_test_record("#{@prefix}:a3", name: 'A3')
SimpleModelMigration.processed_keys = []
migration = SimpleModelMigration.new(run: true)
migration.prepare
migration.migrate
migration.total_scanned
#=> 3

## Model migration tracks records_needing_update
cleanup_records
create_test_record("#{@prefix}:b1")
create_test_record("#{@prefix}:b2")
SimpleModelMigration.processed_keys = []
migration = SimpleModelMigration.new(run: true)
migration.prepare
migration.migrate
migration.records_needing_update
#=> 2

## Model migration increments records_updated via track_stat
cleanup_records
create_test_record("#{@prefix}:c1")
SimpleModelMigration.processed_keys = []
migration = SimpleModelMigration.new(run: true)
migration.prepare
migration.migrate
migration.records_updated
#=> 1

## Model migration returns true when no errors
cleanup_records
create_test_record("#{@prefix}:d1")
SimpleModelMigration.processed_keys = []
migration = SimpleModelMigration.new(run: true)
migration.prepare
migration.migrate
#=> true

## Model migration handles errors and increments error_count
cleanup_records
create_test_record("#{@prefix}:e1", name: 'trigger_error')
ErrorModelMigration.error_triggered = false
migration = ErrorModelMigration.new(run: true)
migration.prepare
migration.migrate
[ErrorModelMigration.error_triggered, migration.error_count]
#=> [true, 1]

## Model migration returns false when errors occurred
cleanup_records
create_test_record("#{@prefix}:f1", name: 'trigger_error')
ErrorModelMigration.error_triggered = false
migration = ErrorModelMigration.new(run: true)
migration.prepare
migration.migrate
#=> false

## Model migration continues after errors
cleanup_records
create_test_record("#{@prefix}:g1", name: 'trigger_error')
create_test_record("#{@prefix}:g2", name: 'Normal')
ErrorModelMigration.error_triggered = false
migration = ErrorModelMigration.new(run: true)
migration.prepare
migration.migrate
[migration.error_count, migration.records_needing_update]
#=> [1, 2]

## Skipping migration respects dry_run mode
cleanup_records
create_test_record("#{@prefix}:h1", status: 'active')
SkippingModelMigration.skipped_count = 0
SkippingModelMigration.processed_count = 0
migration = SkippingModelMigration.new(run: false)
migration.prepare
migration.migrate
[migration.dry_run?, SkippingModelMigration.processed_count]
#=> [true, 0]

## Skipping migration executes in actual_run mode
cleanup_records
create_test_record("#{@prefix}:i1", status: 'active')
SkippingModelMigration.skipped_count = 0
SkippingModelMigration.processed_count = 0
migration = SkippingModelMigration.new(run: true)
migration.prepare
migration.migrate
SkippingModelMigration.processed_count
#=> 1

## Skipping migration tracks skipped records
cleanup_records
create_test_record("#{@prefix}:j1", status: 'skip_me')
create_test_record("#{@prefix}:j2", status: 'active')
SkippingModelMigration.skipped_count = 0
SkippingModelMigration.processed_count = 0
migration = SkippingModelMigration.new(run: true)
migration.prepare
migration.migrate
[SkippingModelMigration.skipped_count, SkippingModelMigration.processed_count]
#=> [1, 1]

## Custom load_from_key is called
cleanup_records
create_test_record("#{@prefix}:k1")
CustomLoadMigration.custom_load_called = false
migration = CustomLoadMigration.new(run: true)
migration.prepare
migration.migrate
CustomLoadMigration.custom_load_called
#=> true

## migration_needed? default returns true
migration = SimpleModelMigration.new
migration.prepare
migration.migration_needed?
#=> true

## NotNeeded migration is skipped by run
cleanup_records
result = NotNeededMigration.run(run: true)
result.nil?
#=> true

## track_stat correctly increments stats
migration = SimpleModelMigration.new
migration.track_stat(:custom_stat)
migration.track_stat(:custom_stat, 5)
migration.stats[:custom_stat]
#=> 6

## interactive mode defaults to false
migration = SimpleModelMigration.new
migration.prepare
migration.interactive
#=> false

## dbclient returns Redis connection
migration = SimpleModelMigration.new
migration.prepare
migration.send(:dbclient).respond_to?(:scan)
#=> true

## validate_before_transform? defaults to false
migration = SimpleModelMigration.new
migration.validate_before_transform?
#=> false

## validate_after_transform? defaults to false
migration = SimpleModelMigration.new
migration.validate_after_transform?
#=> false

## Base process_record raises NotImplementedError
class BareModel < Familia::Migration::Model
  self.migration_id = 'bare_model'
  def prepare
    @model_class = ModelTestRecord
  end
end
migration = BareModel.new
begin
  migration.process_record(nil, 'key')
  false
rescue NotImplementedError
  true
end
#=> true

## Base prepare raises NotImplementedError
begin
  Familia::Migration::Model.new.prepare
  false
rescue NotImplementedError
  true
end
#=> true

## scan_pattern is set from model_class after validation
cleanup_records
migration = SimpleModelMigration.new
migration.prepare
migration.send(:validate_model_class!)
migration.scan_pattern.include?('modeltestrecord')
#=> true

cleanup_records
Familia::Migration.migrations.replace(@initial_migrations)
