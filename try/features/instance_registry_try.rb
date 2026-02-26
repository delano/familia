# try/features/instance_registry_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class RegistryTestModel < Familia::Horreum
  identifier_field :rid
  field :rid
  field :name
  field :status
end

# Clean up any leftover test data
begin
  existing = Familia.dbclient.keys('registrytestmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RegistryTestModel.instances.clear

## save adds to instances sorted set
@obj1 = RegistryTestModel.new(rid: 'reg-save-1', name: 'Save Test')
@obj1.save
RegistryTestModel.instances.member?('reg-save-1')
#=> true

## commit_fields adds to instances sorted set
@obj2 = RegistryTestModel.new(rid: 'reg-commit-1', name: 'Commit Test')
@obj2.commit_fields
RegistryTestModel.instances.member?('reg-commit-1')
#=> true

## batch_update adds to instances sorted set
@obj3 = RegistryTestModel.new(rid: 'reg-batch-1', name: 'Batch Test')
@obj3.save
@obj3.batch_update(name: 'Updated Name')
RegistryTestModel.instances.member?('reg-batch-1')
#=> true

## save_fields adds to instances sorted set
@obj4 = RegistryTestModel.new(rid: 'reg-savefields-1', name: 'SaveFields Test')
@obj4.save
@obj4.name = 'Updated'
@obj4.save_fields(:name)
RegistryTestModel.instances.member?('reg-savefields-1')
#=> true

## save_if_not_exists adds to instances sorted set
@obj5 = RegistryTestModel.new(rid: 'reg-sine-1', name: 'SINE Test')
@obj5.save_if_not_exists!
RegistryTestModel.instances.member?('reg-sine-1')
#=> true

## fast writer (field!) adds to instances sorted set
@obj6 = RegistryTestModel.new(rid: 'reg-fast-1', name: 'Fast Write Test')
@obj6.save
@obj6.name!('Fast Updated')
RegistryTestModel.instances.member?('reg-fast-1')
#=> true

## instance destroy! removes from instances sorted set
@obj7 = RegistryTestModel.new(rid: 'reg-destroy-1', name: 'Destroy Test')
@obj7.save
RegistryTestModel.instances.member?('reg-destroy-1')
#=> true

## After destroy!, instance is no longer in instances
@obj7.destroy!
RegistryTestModel.instances.member?('reg-destroy-1')
#=> false

## class-level destroy! removes from instances sorted set
@obj8 = RegistryTestModel.new(rid: 'reg-cls-destroy-1', name: 'Class Destroy Test')
@obj8.save
RegistryTestModel.instances.member?('reg-cls-destroy-1')
#=> true

## After class-level destroy!, instance is no longer in instances
RegistryTestModel.destroy!('reg-cls-destroy-1')
RegistryTestModel.instances.member?('reg-cls-destroy-1')
#=> false

## touch_instances! is idempotent (does not duplicate)
@obj9 = RegistryTestModel.new(rid: 'reg-idempotent-1', name: 'Idempotent Test')
@obj9.save
count_before = RegistryTestModel.instances.size
@obj9.touch_instances!
@obj9.touch_instances!
RegistryTestModel.instances.size == count_before
#=> true

## remove_from_instances! removes from instances without deleting data
@obj10 = RegistryTestModel.new(rid: 'reg-unreg-1', name: 'Unregister Test')
@obj10.save
@obj10.remove_from_instances!
RegistryTestModel.instances.member?('reg-unreg-1')
#=> false

## After remove_from_instances!, the hash key still exists in Redis
@obj10.exists?
#=> true

## Teardown
begin
  existing = Familia.dbclient.keys('registrytestmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
RegistryTestModel.instances.clear
