require_relative '../helpers/test_helpers'
require 'tmpdir'

@tempdir = Dir.mktmpdir('familia_reload_test')
@test_file = File.join(@tempdir, 'test_reloadable_class.rb')
@test_class_name = 'TestReloadableClass'

File.write(@test_file, <<~RUBY)
  class #{@test_class_name} < Familia::Horreum
    field :name
    field :value
  end
RUBY

class ::TestReloadableClassA < Familia::Horreum
  field :data
end

class ::TestReloadableClassB < Familia::Horreum
  field :info
end

class ::TestStringSymbol < Familia::Horreum
  field :data_field
end

## Load a test class and add it to Familia.members for tracking
load @test_file
Familia.add_member(TestReloadableClass)
TestReloadableClass.new(name: "test", value: "initial").class.name
#=> "TestReloadableClass"

## unload_member removes a specific class constant
Familia.unload_member(@test_class_name)
TestReloadableClass
#=!> NameError

## Reload the class after unloading
load @test_file
TestReloadableClass.new(name: "test", value: "reloaded").class.name
#=> "TestReloadableClass"

## Set up member tracking for batch unloading test
Familia.instance_variable_set(:@members, [TestReloadableClassA, TestReloadableClassB])
Familia.members
#=> [TestReloadableClassA, TestReloadableClassB]

## unload! removes all tracked member classes
Familia.unload!
Familia.members
#=> []

## Verify both classes were unloaded
errors = []
begin
  TestReloadableClassA
rescue NameError
  errors << "A"
end

begin
  TestReloadableClassB
rescue NameError
  errors << "B"
end

errors.sort
#=> ["A", "B"]

## unload_member handles string and symbol inputs
Familia.unload_member("TestStringSymbol")
begin
  TestStringSymbol
rescue NameError => e
  e.message.include?("TestStringSymbol")
end
#=> true

# Cleanup test directory
FileUtils.rm_rf(@tempdir)
