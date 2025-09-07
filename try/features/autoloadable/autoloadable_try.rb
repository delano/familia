# try/features/autoloadable/autoloadable_try.rb

require_relative '../../../lib/familia'
require 'fileutils'
require 'tmpdir'

class ::TestAutoloadableFeature < Familia::Horreum
  include Familia::Features::Autoloadable
end

# Test module that would be included in DataType (should not crash)
class ::TestDataTypeFeature < Familia::DataType
  include Familia::Features::Autoloadable
end


# Create test directory structure in a temp location for autoloadable testing
@test_dir = Dir.mktmpdir('familia_autoloadable_test')
@test_model_file = File.join(@test_dir, 'test_model.rb')
@test_feature_file = File.join(@test_dir, 'test_model', 'safe_dump_custom.rb')
@feature_dir = File.join(@test_dir, 'test_model')
@features_subdir = File.join(@test_dir, 'test_model', 'features')
@global_features_dir = File.join(@test_dir, 'features')

# Create directory structure
FileUtils.mkdir_p(@feature_dir)
FileUtils.mkdir_p(@features_subdir)
FileUtils.mkdir_p(@global_features_dir)

# Write test model file
File.write(@test_model_file, <<~RUBY)
  class TestModel < Familia::Horreum
    field :name
    field :email

    feature :safe_dump
  end
RUBY

# Write autoloadable test feature file
File.write(@test_feature_file, <<~RUBY)
  class TestModel
    safe_dump_fields :name, :email

    def custom_method
      "autoloaded"
    end
  end
RUBY

# Write features subdirectory file
@features_subdir_file = File.join(@features_subdir, 'safe_dump_advanced.rb')
File.write(@features_subdir_file, <<~RUBY)
  class TestModel
    safe_dump_field :computed_field, lambda { |obj| "computed_\#{obj.name}" }
  end
RUBY

# Write global features directory file
@global_features_file = File.join(@global_features_dir, 'safe_dump_global.rb')
File.write(@global_features_file, <<~RUBY)
  class TestModel
    safe_dump_field :global_field, lambda { |obj| "global_\#{obj.email}" }
  end
RUBY

# Create a test feature module with Autoloadable
@test_autoloadable_module = Module.new do
  include Familia::Features::Autoloadable

  def self.name
    'TestFeature'
  end
end

## Test feature name detection from module name
test_feature_name = @test_autoloadable_module.class_eval do
  name.split('::').last.snake_case
end
test_feature_name
#=> "test_feature"

## Test SafeDump feature name detection
safe_dump_feature_name = Familia::Features::SafeDump.name.split('::').last.snake_case
safe_dump_feature_name
#=> "safe_dump"

## Test that Autoloadable can be included in a feature module
TestAutoloadableFeature.ancestors.include?(Familia::Features::Autoloadable)
#=> true

## Test that feature_options method exists on Horreum classes
TestModelForFeatureOptions = Class.new(Familia::Horreum) do
  field :test_field
end

TestModelForFeatureOptions.respond_to?(:feature_options)
#=> true

## Test that feature_options returns empty hash for unknown features
TestModelForFeatureOptions.feature_options(:unknown_feature)
#=> {}

## Test that feature_options stores calling location when feature is used
TestModelForFeatureOptions.class_eval do
  feature :safe_dump
end
#=>

## Test that feature_options contains calling_location information
options = TestModelForFeatureOptions.feature_options(:safe_dump)
options.key?(:calling_location)
#=> true

## Test that calling_location is a string
options[:calling_location].is_a?(String)
#=> true

## Test autoloading works by requiring the test model file
original_safe_dump_fields = nil
test_model_instance = nil

begin
  # Load the test model which should trigger autoloading
  require @test_model_file

  # Create instance to test functionality
  test_model_instance = TestModel.new(name: 'John', email: 'john@example.com')

  # Check that autoloaded methods are available
  test_model_instance.respond_to?(:custom_method)
rescue LoadError => e
  false
end
#=> true

## Test that autoloaded custom method works
test_model_instance.custom_method
#=> "autoloaded"

## Test that safe_dump fields were set by autoloaded file
TestModel.safe_dump_field_names.sort
#=> [:computed_field, :email, :global_field, :name]

## Test that safe_dump works with autoloaded fields
dump_result = test_model_instance.safe_dump
dump_result.keys.sort
#=> [:computed_field, :email, :global_field, :name]

## Test computed field value
dump_result[:computed_field]
#=> "computed_John"

## Test global field value
dump_result[:global_field]
#=> "global_john@example.com"

## Test that autoloadable skips DataType classes without feature_options
TestDataType = Class.new(Familia::DataType::String)
TestDataType.respond_to?(:feature_options)
#=> false

## Test that including autoloadable feature in DataType doesn't raise error
begin
  TestDataType.include(TestDataTypeFeature)
  true
rescue => e
  false
end
#=> true

## Test file pattern matching with different directory structures
patterns_found = []

# Test the pattern generation logic manually
base_dir = @test_dir
model_name = 'test_model'
feature_name = 'safe_dump'

pattern1 = File.join(base_dir, model_name, "#{feature_name}_*.rb")
pattern2 = File.join(base_dir, model_name, 'features', "#{feature_name}_*.rb")
pattern3 = File.join(base_dir, 'features', "#{feature_name}_*.rb")

## Test that pattern1 finds one file (model/feature_name_*.rb)
Dir.glob(pattern1).length
#=> 1

## Test that pattern2 finds one file (model/features/feature_name_*.rb)
Dir.glob(pattern2).length
#=> 1

## Test that pattern3 finds one file (features/feature_name_*.rb)
Dir.glob(pattern3).length
#=> 1

# Cleanup test files and directories
FileUtils.rm_rf(@test_dir)
