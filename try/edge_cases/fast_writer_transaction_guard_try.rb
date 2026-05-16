require 'base64'
require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Configure encryption for encrypted field tests
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Test class for fast writer transaction/pipeline guards
class FastWriterGuardTest < Familia::Horreum
  identifier_field :testid
  field :testid
  field :name
  field :value
end

# Test class for encrypted fast writer guards
class EncryptedFastWriterGuardTest < Familia::Horreum
  feature :encrypted_fields
  identifier_field :testid
  field :testid
  encrypted_field :secret
end

# Clean slate
@testobj = FastWriterGuardTest.new(testid: 'fw-guard-test', name: 'initial')
@testobj.destroy!
@testobj.save

## Fast writer raises OperationModeError inside transaction
begin
  @testobj.transaction do
    @testobj.name!('inside-transaction')
  end
  :should_have_raised
rescue Familia::OperationModeError => e
  e.message.include?('Cannot call fast writer')
end
#=> true

## Fast writer raises OperationModeError inside pipeline
begin
  @testobj.pipelined do
    @testobj.name!('inside-pipeline')
  end
  :should_have_raised
rescue Familia::OperationModeError => e
  e.message.include?('Cannot call fast writer')
end
#=> true

## Transaction error message suggests multi_field_update or commit_fields
begin
  @testobj.transaction do
    @testobj.name!('inside-transaction')
  end
  :should_have_raised
rescue Familia::OperationModeError => e
  e.message.include?('multi_field_update') && e.message.include?('commit_fields')
end
#=> true

## Pipeline error message suggests restructuring (not multi_field_update)
begin
  @testobj.pipelined do
    @testobj.name!('inside-pipeline')
  end
  :should_have_raised
rescue Familia::OperationModeError => e
  e.message.include?('Restructure') && !e.message.include?('multi_field_update')
end
#=> true

## Fast writer works normally outside transaction
@testobj.value!('direct-write')
@testobj.value
#=> 'direct-write'

## Fast writer as getter works inside transaction (returns Future)
result = nil
@testobj.transaction do
  result = @testobj.value!
end
result.is_a?(Redis::Future) || result == 'direct-write'
#=> true

## Fast writer works after transaction completes
@testobj.transaction do
  @testobj.hset(:name, '"modified"')
end
@testobj.value!('after-transaction')
@testobj.value
#=> 'after-transaction'

## Encrypted fast writer raises OperationModeError inside transaction
@encrypted = EncryptedFastWriterGuardTest.new(testid: 'enc-fw-guard-test')
@encrypted.destroy!
@encrypted.save
begin
  @encrypted.transaction do
    @encrypted.secret!('sensitive-data')
  end
  :should_have_raised
rescue Familia::OperationModeError => e
  e.message.include?('Cannot call fast writer')
end
#=> true

## Encrypted fast writer raises OperationModeError inside pipeline
begin
  @encrypted.pipelined do
    @encrypted.secret!('sensitive-data')
  end
  :should_have_raised
rescue Familia::OperationModeError => e
  e.message.include?('Cannot call fast writer')
end
#=> true

## Cleanup
@testobj.destroy!
@encrypted.destroy!
true
#=> true

# Teardown - restore global encryption config so test order is not a factor
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
