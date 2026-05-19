require 'base64'
require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Configure encryption for encrypted field tests
test_keys = { v1: Base64.strict_encode64('a' * 32) }
Familia.config.encryption_keys = test_keys
Familia.config.current_key_version = :v1

# Test class for fast writer transaction/pipeline behavior
class FastWriterGuardTest < Familia::Horreum
  identifier_field :testid
  field :testid
  field :name
  field :value
end

# Test class for encrypted fast writer behavior
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

## Fast writer inside transaction returns Redis::Future
result = nil
@testobj.transaction do
  result = @testobj.name!('inside-transaction')
end
result.is_a?(Redis::Future)
#=> true

## Fast writer value is persisted after transaction completes
@testobj.refresh
@testobj.name
#=> 'inside-transaction'

## Fast writer inside pipeline returns Redis::Future
result = nil
@testobj.pipelined do
  result = @testobj.value!('inside-pipeline')
end
result.is_a?(Redis::Future)
#=> true

## Fast writer value is persisted after pipeline completes
@testobj.refresh
@testobj.value
#=> 'inside-pipeline'

## Fast writer works normally outside transaction (returns boolean)
result = @testobj.name!('direct-write')
[true, false].include?(result)
#=> true

## Fast writer as getter works inside transaction (returns Future)
result = nil
@testobj.transaction do
  result = @testobj.value!
end
result.is_a?(Redis::Future) || result == 'inside-pipeline'
#=> true

## Fast writer works after transaction completes
@testobj.transaction do
  @testobj.hset(:name, '"modified"')
end
@testobj.value!('after-transaction')
@testobj.value
#=> 'after-transaction'

## Encrypted fast writer inside transaction returns Redis::Future
@encrypted = EncryptedFastWriterGuardTest.new(testid: 'enc-fw-guard-test')
@encrypted.destroy!
@encrypted.save
result = nil
@encrypted.transaction do
  result = @encrypted.secret!('sensitive-data')
end
result.is_a?(Redis::Future)
#=> true

## Encrypted fast writer value is persisted after transaction
@encrypted.refresh
@encrypted.secret.to_s.length > 0
#=> true

## Encrypted fast writer inside pipeline returns Redis::Future
result = nil
@encrypted.pipelined do
  result = @encrypted.secret!('updated-secret')
end
result.is_a?(Redis::Future)
#=> true

## Cleanup
@testobj.destroy!
@encrypted.destroy!
true
#=> true

# Teardown - restore global encryption config so test order is not a factor
Familia.config.encryption_keys = nil
Familia.config.current_key_version = nil
