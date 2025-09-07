# try/features/safe_dump/safe_dump_autoloading_try.rb

require_relative '../../../lib/familia'
require 'fileutils'
require 'tmpdir'

# Create test directory structure for SafeDump autoloading testing
@test_dir = Dir.mktmpdir('familia_safe_dump_autoload_test')
@model_file = File.join(@test_dir, 'test_safe_dump_model.rb')
@extension_file = File.join(@test_dir, 'test_safe_dump_model', 'safe_dump_extensions.rb')
@extension_dir = File.join(@test_dir, 'test_safe_dump_model')

# Create directory structure
FileUtils.mkdir_p(@extension_dir)

# Write test model file that uses SafeDump
File.write(@model_file, <<~RUBY)
  class TestSafeDumpModel < Familia::Horreum
    field :name
    field :email
    field :secret

    feature :safe_dump
  end
RUBY

# Write extension file (pattern: model_name/safe_dump_*.rb)
File.write(@extension_file, <<~RUBY)
  class TestSafeDumpModel
    # Define safe dump fields
    safe_dump_fields :name, :email

    # Add method to verify autoloading worked
    def extension_loaded?
      true
    end
  end
RUBY

## Test that SafeDump includes Autoloadable
Familia::Features::SafeDump.ancestors.include?(Familia::Features::Autoloadable)
#=> true

## Test that SafeDump has post_inclusion_autoload capability
Familia::Features::SafeDump.respond_to?(:post_inclusion_autoload)
#=> true

## Test SafeDump autoloading by loading model file
@model_instance = nil

begin
  require @model_file
  @model_instance = TestSafeDumpModel.new(
    name: 'John Doe',
    email: 'john@example.com',
    secret: 'hidden data'
  )
  true
rescue => e
  false
end
#=> true

## Test that autoloaded extension method is available
@model_instance.respond_to?(:extension_loaded?)
#=> true

## Test autoloaded extension method works
@model_instance.extension_loaded?
#=> true

## Test that model was created successfully
@model_instance.class.name
#=> "TestSafeDumpModel"

## Test that feature_options were set up correctly
TestSafeDumpModel.respond_to?(:feature_options)
#=> true

## Test that safe_dump fields were loaded from extension file
TestSafeDumpModel.safe_dump_field_names.sort
#=> [:email, :name]

## Test that safe_dump functionality works with autoloaded fields
@dump_result = @model_instance.safe_dump
@dump_result.keys.sort
#=> [:email, :name]

## Test that only safe fields are dumped
@dump_result[:name]
#=> "John Doe"

## Test that email field is included
@dump_result[:email]
#=> "john@example.com"

## Test that secret field is excluded (not in safe_dump_fields)
@dump_result.key?(:secret)
#=> false

## Test that feature_options can be retrieved
@options = TestSafeDumpModel.feature_options(:safe_dump)
@options.is_a?(Hash)
#=> true

## Test safe_dump feature is recognized
TestSafeDumpModel.features_enabled.include?(:safe_dump)
#=> true

# Cleanup test files and directories
FileUtils.rm_rf(@test_dir)
