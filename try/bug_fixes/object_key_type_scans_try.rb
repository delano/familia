# try/bug_fixes/object_key_type_scans_try.rb
#
# frozen_string_literal: true

# The methods that enumerate a class's objects match "<prefix>:*:<suffix>"
# and read each key as an object hash. A multi_index bucket whose field
# value equals the suffix also matches: with role "object", the bucket
# "otk_user:role_index:object" (class-level) and
# "otk_co:c-1:dept_index:object" (within a scope) parsed as the objects
# "role_index" and "c-1:dept_index". audit_instances reported them as
# missing from the timeline, scan_count and keys_count counted them, and
# all, health_check, repair_instances! and rebuild_instances raised
# WRONGTYPE loading them.
# These methods now keep only keys that hold a hash
# (Familia::Horreum::OBJECT_KEY_TYPE).

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

# Class-level multi_index plus a unique index for the SCAN rebuild.
class ::OtkUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  field :email
  multi_index :role, :role_index
  unique_index :email, :email_lookup
end

# Scope class for the instance-scoped index.
class ::OtkCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
end

# Indexed class whose dept_index buckets live under each company.
class ::OtkEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::OtkCo
  participates_in ::OtkCo, :staff
end

# Model migration that records the keys it processes.
class ::OtkMigration < Familia::Migration::Model
  self.migration_id = 'otk_migration'

  class << self
    attr_accessor :processed_keys
  end
  self.processed_keys = []

  def prepare
    @model_class = ::OtkUser
    @batch_size = 10
  end

  def process_record(_obj, key)
    self.class.processed_keys << key
    track_stat(:records_updated)
  end
end

# Model migration with a custom pattern, which scans every key type.
class ::OtkCustomMigration < Familia::Migration::Model
  self.migration_id = 'otk_custom_migration'

  class << self
    attr_accessor :processed_keys
  end
  self.processed_keys = []

  def prepare
    @model_class = ::OtkUser
    @scan_pattern = 'otk_user:role_index:*'
  end

  def load_from_key(key)
    key
  end

  def process_record(_obj, key)
    self.class.processed_keys << key
  end
end

@initial_migrations = Familia::Migration.migrations.dup
delete_test_dbkeys(OtkUser, OtkCo, OtkEmp)

@u1 = OtkUser.new(uid: 'u1', role: 'object', email: 'u1@example.com')
@u1.save
OtkUser.rebuild_role_index
@c1 = OtkCo.new(cid: 'c-1')
@c1.save
@e1 = OtkEmp.new(eid: 'e1', dept: 'object')
@e1.save
@e1.add_to_otk_co_staff(@c1)
@c1.rebuild_dept_index

## Both buckets exist and match the object key pattern
[
  Familia.dbclient.type('otk_user:role_index:object'),
  Familia.dbclient.type('otk_co:c-1:dept_index:object'),
  OtkUser.find_keys('object').sort,
]
#=> ["set", "set", ["otk_user:role_index:object", "otk_user:u1:object"]]

## audit_instances does not report a class-level bucket as a missing object
OtkUser.audit_instances.values_at(:phantoms, :missing, :count_scan)
#=> [[], [], 1]

## audit_instances does not report an instance-scoped bucket as a missing object
OtkCo.audit_instances.values_at(:phantoms, :missing, :count_scan)
#=> [[], [], 1]

## repair_instances! does not raise and adds no ghost identifier
OtkCo.repair_instances!
OtkCo.instances.members
#=> ["c-1"]

## rebuild_instances skips a class-level bucket
[OtkUser.rebuild_instances, OtkUser.instances.members]
#=> [1, ["u1"]]

## rebuild_instances skips an instance-scoped bucket
[OtkCo.rebuild_instances, OtkCo.instances.members]
#=> [1, ["c-1"]]

## health_check completes for the class with the bucket
OtkUser.health_check.instances.values_at(:phantoms, :missing)
#=> [[], []]

## all loads only the objects
[OtkUser.all.map(&:uid), OtkCo.all.map(&:cid)]
#=> [["u1"], ["c-1"]]

## scan_count and keys_count count only object hashes
[OtkUser.scan_count, OtkUser.keys_count, OtkCo.scan_count, OtkCo.keys_count]
#=> [1, 1, 1, 1]

## scan_any? and keys_any? do not see a bucket as an object
[OtkUser.scan_any?('role_index'), OtkUser.keys_any?('role_index'), OtkUser.scan_any?('u*')]
#=> [false, false, true]

## scan_keys yields only object keys
OtkCo.scan_keys.to_a
#=> ["otk_co:c-1:object"]

## The SCAN fallback of a unique index rebuild skips the bucket
OtkUser.email_lookup.clear
@count = Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_scan(
  OtkUser, :email, :add_to_class_email_lookup, OtkUser.email_lookup
)
[@count, OtkUser.email_lookup.all]
#=> [1, {"u1@example.com"=>"u1"}]

## A model migration with the default pattern processes only object hashes
OtkMigration.processed_keys = []
@migration = OtkMigration.new(run: true)
@migration.prepare
@migration.migrate
[@migration.scan_type, @migration.error_count, OtkMigration.processed_keys]
#=> ["hash", 0, ["otk_user:u1:object"]]

## A model migration with a custom pattern still scans every type
OtkCustomMigration.processed_keys = []
@custom = OtkCustomMigration.new(run: true)
@custom.prepare
@custom.migrate
[@custom.scan_type, OtkCustomMigration.processed_keys]
#=> [nil, ["otk_user:role_index:object"]]

## The buckets are unchanged
[OtkUser.find_all_by_role('object').map(&:uid), @c1.find_all_by_dept('object').map(&:eid)]
#=> [["u1"], ["e1"]]

delete_test_dbkeys(OtkUser, OtkCo, OtkEmp)
Familia::Migration.migrations.replace(@initial_migrations)
