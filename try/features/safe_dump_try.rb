# try/features/safe_dump_try.rb

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

Familia.debug = false

# Test SafeDump feature functionality

# Define a test class with SafeDump feature
class SafeDumpTest < Familia::Horreum
  feature :safe_dump
  identifier :id
  field :id
  field :name
  field :email
  field :secret_data

  @safe_dump_fields = [
    :id,
    :name,
    { :display_name => ->(obj) { "#{obj.name} (#{obj.id})" } },
    { :has_email => ->(obj) { !obj.email.nil? && !obj.email.empty? } }
  ]

  def active?
    true
  end
end

# Setup test object
@test_obj = SafeDumpTest.new
@test_obj.id = "safe_test_1"
@test_obj.name = "Test User"
@test_obj.email = "test@example.com"
@test_obj.secret_data = "sensitive_info"

## Class has SafeDump methods
SafeDumpTest.respond_to?(:safe_dump_fields)
#=> true

## Class has safe_dump_field_map method
SafeDumpTest.respond_to?(:safe_dump_field_map)
#=> true

## Object has safe_dump method
@test_obj.respond_to?(:safe_dump)
#=> true

## safe_dump_fields returns field names only
fields = SafeDumpTest.safe_dump_fields
fields
#=> [:id, :name, :display_name, :has_email]

## safe_dump_field_map returns callable map
field_map = SafeDumpTest.safe_dump_field_map
field_map.keys.sort
#=> [:display_name, :has_email, :id, :name]

## safe_dump_field_map values are callable
field_map = SafeDumpTest.safe_dump_field_map
field_map[:id]
#==> _.respond_to?(:call)

## safe_dump returns hash with safe fields only
dump = @test_obj.safe_dump
dump.keys.sort
#=> [:display_name, :has_email, :id, :name]

## safe_dump includes basic field values
dump = @test_obj.safe_dump
[dump[:id], dump[:name]]
#=> ["safe_test_1", "Test User"]

## safe_dump includes computed field values
dump = @test_obj.safe_dump
dump[:display_name]
#=> "Test User (safe_test_1)"

## safe_dump includes lambda field values
dump = @test_obj.safe_dump
dump[:has_email]
#=> true

## safe_dump excludes non-whitelisted fields
dump = @test_obj.safe_dump
dump.key?(:secret_data)
#=> false

## safe_dump excludes email field not in whitelist
dump = @test_obj.safe_dump
dump.key?(:email)
#=> false

## Safe dump works with nil values
@test_obj.email = nil
dump = @test_obj.safe_dump
dump[:has_email]
#=> false

## Safe dump works with empty values
@test_obj.email = ""
dump = @test_obj.safe_dump
dump[:has_email]
#=> false

## Can define safe_dump_fields with set_safe_dump_fields
class DynamicSafeDump < Familia::Horreum
  feature :safe_dump
  identifier :id
  field :id
  field :data
end

DynamicSafeDump.set_safe_dump_fields(:id, :data)
DynamicSafeDump.safe_dump_fields
#=> [:id, :data]

## Class with no safe_dump_fields defined has empty array
class EmptySafeDump < Familia::Horreum
  feature :safe_dump
  identifier :id
  field :id
end

EmptySafeDump.safe_dump_fields
#=> []

## Empty safe_dump returns empty hash
@empty_obj = EmptySafeDump.new
@empty_obj.id = "empty_test"
@empty_obj.safe_dump
#=> {}

# Cleanup
@test_obj.destroy! if @test_obj
@empty_obj.destroy! if @empty_obj
