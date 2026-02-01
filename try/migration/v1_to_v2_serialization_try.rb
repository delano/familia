# try/migration/v1_to_v2_serialization_try.rb
#
# frozen_string_literal: true

# Tests for V1 to V2 Serialization Migration
#
# Demonstrates migrating Familia Horreum objects from v1.x serialization
# (plain strings via distinguisher) to v2.0 serialization (universal JSON).

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'
require_relative '../../examples/migrations/v1_to_v2_serialization_migration'

Familia.debug = false

@redis = Familia.dbclient
@test_id = "#{Process.pid}_#{Time.now.to_i}"
@prefix = "familia:test:v1v2:#{@test_id}"

@initial_migrations = Familia::Migration.migrations.dup

# Test model for migration testing
class V1V2TestRecord < Familia::Horreum
  identifier_field :record_id
  field :record_id
  field :name           # String field
  field :age            # Integer field
  field :balance        # Float field
  field :active         # Boolean field
  field :verified       # Boolean field (false)
  field :settings       # Hash field
  field :tags           # Array field
  field :notes          # String or nil
  field :created_at     # Timestamp (integer)
end

# Concrete migration for V1V2TestRecord
class V1V2TestMigration < V1ToV2SerializationMigration
  self.migration_id = 'test_v1v2_migration'
  self.description = 'Test migration for v1 to v2 serialization'

  def prepare
    @model_class = V1V2TestRecord
    @batch_size = 10
    super
  end

  def field_types_for_model
    {
      record_id: :string,
      name: :string,
      age: :integer,
      balance: :float,
      active: :boolean,
      verified: :boolean,
      settings: :hash,
      tags: :array,
      notes: :string,
      created_at: :timestamp
    }
  end
end

# Helper to create v1.x format data directly in Redis
# Simulates how v1.x Familia stored values
def create_v1_record(suffix, data = {})
  id = "#{@test_id}_#{suffix}"
  # Use the model's actual prefix to match what the migration scans for
  prefix = V1V2TestRecord.prefix
  dbkey = "#{prefix}:#{id}:object"

  # v1.x serialization: plain strings, no JSON for simple types
  v1_data = {
    'record_id' => id,
    'name' => data[:name] || 'Test User',
    'age' => (data[:age] || 0).to_s,                    # v1: Integer as string
    'balance' => (data[:balance] || 0.0).to_s,          # v1: Float as string
    'active' => (data[:active] || false).to_s,          # v1: Boolean as "true"/"false"
    'verified' => (data[:verified] || false).to_s,      # v1: Boolean as "true"/"false"
    'settings' => Familia::JsonSerializer.dump(data[:settings] || {}),  # v1: Hash already JSON
    'tags' => Familia::JsonSerializer.dump(data[:tags] || []),          # v1: Array already JSON
    'created_at' => (data[:created_at] || 0).to_s       # v1: Timestamp as string
  }

  # Add notes only if present (v1 skipped nil values or stored as "")
  v1_data['notes'] = data[:notes] || '' if data.key?(:notes)

  @redis.hmset(dbkey, *v1_data.flatten)

  # Register in instances sorted set (zset) for migration to find
  # Familia uses zset for instances tracking with timestamp as score
  @redis.zadd("#{prefix}:instances", Time.now.to_f, id)

  { dbkey: dbkey, id: id }
end

# Helper to read raw Redis values (bypass Familia)
def read_raw_redis(dbkey)
  @redis.hgetall(dbkey)
end

# Helper to load a record from the dbkey after migration
# Uses from_redis to load with v2 deserialization
def load_migrated_record(dbkey)
  V1V2TestRecord.from_redis(dbkey)
end

# Helper to cleanup test records
def cleanup_records
  prefix = V1V2TestRecord.prefix
  pattern = "#{prefix}:#{@test_id}_*"
  @redis.keys(pattern).each { |k| @redis.del(k) }
  # Clean up instances zset entries for our test ids
  @redis.zremrangebylex("#{prefix}:instances", "[#{@test_id}_", "[#{@test_id}_\xff")
end

cleanup_records

## V1ToV2SerializationMigration is a subclass of Model
V1ToV2SerializationMigration < Familia::Migration::Model
#=> true

## Base migration_id is set
V1ToV2SerializationMigration.migration_id
#=> '20260201_000000_v1_to_v2_serialization_base'

## Test migration initializes correctly
migration = V1V2TestMigration.new
migration.is_a?(V1ToV2SerializationMigration)
#=> true

## Test migration prepares with field types
migration = V1V2TestMigration.new
migration.prepare
migration.instance_variable_get(:@field_types)[:age]
#=> :integer

## Test migration prepares with batch_size
migration = V1V2TestMigration.new
migration.prepare
migration.batch_size
#=> 10

## Detect type correctly identifies integers
migration = V1V2TestMigration.new
migration.send(:detect_type, '42')
#=> :integer

## Detect type correctly identifies negative integers
migration = V1V2TestMigration.new
migration.send(:detect_type, '-123')
#=> :integer

## Detect type correctly identifies floats
migration = V1V2TestMigration.new
migration.send(:detect_type, '3.14')
#=> :float

## Detect type correctly identifies booleans
migration = V1V2TestMigration.new
[migration.send(:detect_type, 'true'), migration.send(:detect_type, 'false')]
#=> [:boolean, :boolean]

## Detect type correctly identifies hashes
migration = V1V2TestMigration.new
migration.send(:detect_type, '{"key":"value"}')
#=> :hash

## Detect type correctly identifies arrays
migration = V1V2TestMigration.new
migration.send(:detect_type, '["a","b","c"]')
#=> :array

## Detect type defaults to string for plain text
migration = V1V2TestMigration.new
migration.send(:detect_type, 'hello world')
#=> :string

## Detect type recognizes v2.0 JSON-quoted strings
migration = V1V2TestMigration.new
migration.send(:detect_type, '"already quoted"')
#=> :string

## Parse v1 string value returns string as-is
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, 'hello', :string)
#=> 'hello'

## Parse v1 integer value converts to Integer
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, '42', :integer)
#=> 42

## Parse v1 float value converts to Float
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, '3.14', :float)
#=> 3.14

## Parse v1 boolean true converts to TrueClass
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, 'true', :boolean)
#=> true

## Parse v1 boolean false converts to FalseClass
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, 'false', :boolean)
#=> false

## Parse v1 hash value returns Hash
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, '{"theme":"dark"}', :hash)
#=> {"theme"=>"dark"}

## Parse v1 array value returns Array
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, '["a","b"]', :array)
#=> ["a", "b"]

## Parse v1 timestamp value converts to Integer
migration = V1V2TestMigration.new
migration.send(:parse_v1_value, '1706745600', :timestamp)
#=> 1706745600

## Convert value transforms v1 string to v2 JSON-quoted string
migration = V1V2TestMigration.new
migration.send(:convert_value, 'hello', :string)
#=> '"hello"'

## Convert value transforms v1 integer string to v2 JSON integer
migration = V1V2TestMigration.new
migration.send(:convert_value, '42', :integer)
#=> '42'

## Convert value transforms v1 float string to v2 JSON float
migration = V1V2TestMigration.new
migration.send(:convert_value, '3.14', :float)
#=> '3.14'

## Convert value transforms v1 boolean string to v2 JSON boolean
migration = V1V2TestMigration.new
migration.send(:convert_value, 'true', :boolean)
#=> 'true'

## Convert value transforms empty string (v1 nil) to v2 null
migration = V1V2TestMigration.new
migration.send(:convert_value, '', :string)
#=> 'null'

## Already v2 format detects JSON-quoted strings
migration = V1V2TestMigration.new
migration.prepare
migration.send(:already_v2_format?, '"hello"', :string)
#=> true

## Already v2 format rejects plain strings
migration = V1V2TestMigration.new
migration.prepare
migration.send(:already_v2_format?, 'hello', :string)
#=> false

## Already v2 format accepts JSON hashes
migration = V1V2TestMigration.new
migration.prepare
migration.send(:already_v2_format?, '{"key":"value"}', :hash)
#=> true

## Already v2 format accepts JSON arrays
migration = V1V2TestMigration.new
migration.prepare
migration.send(:already_v2_format?, '["a","b"]', :array)
#=> true

## V1 data is created correctly for testing
cleanup_records
result = create_v1_record('basic', name: 'Alice', age: 30, balance: 99.99, active: true, verified: false)
raw = read_raw_redis(result[:dbkey])
raw['age']
#=> '30'

## V1 data stores boolean as string
cleanup_records
result = create_v1_record('bool', active: true, verified: false)
raw = read_raw_redis(result[:dbkey])
[raw['active'], raw['verified']]
#=> ['true', 'false']

## V1 data stores name as plain string (not JSON-quoted)
cleanup_records
result = create_v1_record('str', name: 'Bob Smith')
raw = read_raw_redis(result[:dbkey])
raw['name']
#=> 'Bob Smith'

## Migration converts v1 integer field to v2 format
cleanup_records
result = create_v1_record('int_test', age: 25)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
# age stays '25' (JSON number, which is the same string representation)
# but now it will be parsed correctly by v2 deserializer
raw['age']
#=> '25'

## Migration converts v1 string field to v2 JSON-quoted format
cleanup_records
result = create_v1_record('str_test', name: 'Charlie')
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
raw['name']
#=> '"Charlie"'

## Migration converts v1 boolean field correctly
cleanup_records
result = create_v1_record('bool_test', active: true)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
# Boolean fields stay as 'true'/'false' (same JSON representation)
raw['active']
#=> 'true'

## Migration converts v1 float field correctly
cleanup_records
result = create_v1_record('float_test', balance: 123.45)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
# Float representation stays the same in JSON
raw['balance']
#=> '123.45'

## Migration converts v1 empty string (nil) to v2 null
cleanup_records
result = create_v1_record('nil_test', notes: nil)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
raw['notes']
#=> 'null'

## Migration preserves v1 hash field (already JSON)
cleanup_records
settings = { 'theme' => 'dark', 'lang' => 'en' }
result = create_v1_record('hash_test', settings: settings)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
# Hash stays as JSON object
Familia::JsonSerializer.parse(raw['settings'])
#=> {"theme"=>"dark", "lang"=>"en"}

## Migration preserves v1 array field (already JSON)
cleanup_records
tags = ['ruby', 'redis', 'orm']
result = create_v1_record('array_test', tags: tags)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
# Array stays as JSON array
Familia::JsonSerializer.parse(raw['tags'])
#=> ["ruby", "redis", "orm"]

## Migrated data loads correctly with v2 deserializer
cleanup_records
result = create_v1_record('load_test', name: 'Diana', age: 28, active: true)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
[record.name, record.age, record.active]
#=> ['Diana', 28, true]

## Migrated integer field returns Integer class
cleanup_records
result = create_v1_record('type_int', age: 35)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
record.age.class
#=> Integer

## Migrated boolean field returns TrueClass
cleanup_records
result = create_v1_record('type_bool', active: true)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
record.active.class
#=> TrueClass

## Migrated boolean false field returns FalseClass
cleanup_records
result = create_v1_record('type_bool_false', verified: false)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
record.verified.class
#=> FalseClass

## Migrated float field returns Float class
cleanup_records
result = create_v1_record('type_float', balance: 99.99)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
record.balance.class
#=> Float

## Migrated nil field returns NilClass
cleanup_records
result = create_v1_record('type_nil', notes: nil)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
record.notes.class
#=> NilClass

## Migration respects dry_run mode (no changes made)
cleanup_records
result = create_v1_record('dry_run', name: 'Eve')
original_name = read_raw_redis(result[:dbkey])['name']
migration = V1V2TestMigration.new(run: false)  # dry run
migration.prepare
migration.migrate
raw = read_raw_redis(result[:dbkey])
raw['name'] == original_name  # Should be unchanged
#=> true

## Migration tracks records_updated statistic
cleanup_records
create_v1_record('stat1', name: 'F1')
create_v1_record('stat2', name: 'F2')
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
migration.records_updated >= 2
#=> true

## Migration tracks fields_converted statistic
# Note: Integer/float fields (age, balance) have same JSON representation in v1 and v2
# Only string fields (record_id, name) need actual conversion (adding JSON quotes)
cleanup_records
create_v1_record('conv1', name: 'G1', age: 20, balance: 10.5)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
migration.stats[:fields_converted] >= 2
#=> true

## Migration processes multiple records correctly
cleanup_records
create_v1_record('multi1', name: 'H1', age: 21)
create_v1_record('multi2', name: 'H2', age: 22)
create_v1_record('multi3', name: 'H3', age: 23)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
migration.total_scanned >= 3
#=> true

## Already migrated records are skipped on re-run
cleanup_records
result = create_v1_record('rerun', name: 'Iris', age: 30)
migration1 = V1V2TestMigration.new(run: true)
migration1.prepare
migration1.migrate
first_converted = migration1.stats[:fields_converted]
migration2 = V1V2TestMigration.new(run: true)
migration2.prepare
migration2.migrate
second_converted = migration2.stats[:fields_converted]
# Second run should convert zero fields (already v2 format)
second_converted
#=> 0

## Complete round-trip: create v1 data, migrate, load with v2, save, reload
cleanup_records
result = create_v1_record('roundtrip',
  name: 'Jack',
  age: 40,
  balance: 500.00,
  active: true,
  verified: false,
  settings: { 'pref' => 'value' },
  tags: ['tag1', 'tag2'],
  created_at: 1706745600
)
migration = V1V2TestMigration.new(run: true)
migration.prepare
migration.migrate
record = V1V2TestRecord.find_by_key(result[:dbkey])
record.name = 'Jack Updated'
record.save
reloaded = V1V2TestRecord.find_by_key(result[:dbkey])
[reloaded.name, reloaded.age.class, reloaded.active.class]
#=> ['Jack Updated', Integer, TrueClass]

cleanup_records
Familia::Migration.migrations.replace(@initial_migrations)
