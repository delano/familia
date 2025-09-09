# try/features/safe_dump/module_based_extensions_try.rb

require_relative '../../../lib/familia'
require 'fileutils'
require 'tmpdir'

# Create test directory structure for module-based SafeDump extensions
@test_dir = Dir.mktmpdir('familia_module_extensions_test')
@model_file = File.join(@test_dir, 'test_model.rb')
@extension_file = File.join(@test_dir, 'test_model', 'safe_dump_extensions.rb')
@extension_dir = File.join(@test_dir, 'test_model')

# Create directory structure
FileUtils.mkdir_p(@extension_dir)

# Write test model file that uses SafeDump
File.write(@model_file, <<~RUBY)
  class TestModel < Familia::Horreum
    field :name
    field :email
    field :secret

    feature :safe_dump
  end
RUBY

# Write extension file using NEW module-based pattern
File.write(@extension_file, <<~RUBY)
  module TestModel::SafeDumpExtensions
    def self.included(base)
      # Define safe dump fields using the DSL
      base.safe_dump_fields :name, :email

      # Add computed field
      base.safe_dump_field :display_name, ->(obj) { "\#{obj.name} <\#{obj.email}>" }
    end

    # Add instance method to verify module inclusion
    def module_extension_loaded?
      true
    end
  end
RUBY

## Test that SafeDump includes Autoloadable
Familia::Features::SafeDump.ancestors.include?(Familia::Features::Autoloadable)
#=> true

## Test module-based autoloading by loading model file
@model_instance = nil

begin
  # Add test directory to load path for extension file loading
  $LOAD_PATH.unshift(@test_dir)

  require @model_file
  @model_instance = TestModel.new(
    name: 'Jane Doe',
    email: 'jane@example.com',
    secret: 'top secret'
  )
  true
rescue => e
  puts "Error: #{e.message}"
  false
end
#=> true

## Test that module extension method is available
@model_instance.respond_to?(:module_extension_loaded?)
#=> true

## Test module extension method works
@model_instance.module_extension_loaded?
#=> true

## Test that safe_dump fields were loaded from module extension
TestModel.safe_dump_field_names.sort
#=> [:display_name, :email, :name]

## Test that safe_dump functionality works with module-loaded fields
@dump_result = @model_instance.safe_dump
@dump_result.keys.sort
#=> [:display_name, :email, :name]

## Test basic field values
[@dump_result[:name], @dump_result[:email]]
#=> ["Jane Doe", "jane@example.com"]

## Test computed field from module
@dump_result[:display_name]
#=> "Jane Doe <jane@example.com>"

## Test that secret field is excluded
@dump_result.key?(:secret)
#=> false

## Test that the module was actually included (not just loaded)
TestModel.included_modules.any? { |mod| mod.name&.include?('SafeDumpExtensions') }
#=> true

# Cleanup test files and directories
FileUtils.rm_rf(@test_dir)
$LOAD_PATH.shift if $LOAD_PATH.first == @test_dir
