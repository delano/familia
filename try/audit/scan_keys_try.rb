# try/audit/scan_keys_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class ScanKeysModel < Familia::Horreum
  identifier_field :skid
  field :skid
  field :name
end

# Clean up
begin
  existing = Familia.dbclient.keys('scan_keys_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
ScanKeysModel.instances.clear

## scan_keys exists as class method
ScanKeysModel.respond_to?(:scan_keys)
#=> true

## scan_keys with no data returns empty enumerator
ScanKeysModel.scan_keys.to_a.size
#=> 0

## Create objects for scan
@sk1 = ScanKeysModel.new(skid: 'sk-1', name: 'One')
@sk1.save
@sk2 = ScanKeysModel.new(skid: 'sk-2', name: 'Two')
@sk2.save
ScanKeysModel.scan_keys.to_a.size
#=> 2

## scan_keys returns enumerator without block
ScanKeysModel.scan_keys.is_a?(Enumerator)
#=> true

## scan_keys yields keys with block
@keys = []
ScanKeysModel.scan_keys { |k| @keys << k }
@keys.size
#=> 2

## scan_keys accepts batch_size
@keys = []
ScanKeysModel.scan_keys('*', batch_size: 1) { |k| @keys << k }
@keys.size
#=> 2

## scan_keys returns matching keys
@keys = ScanKeysModel.scan_keys.to_a.sort
@keys.all? { |k| k.start_with?('scan_keys_model:') }
#=> true

# Teardown
begin
  existing = Familia.dbclient.keys('scan_keys_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
ScanKeysModel.instances.clear
