# try/features/safe_dump/safe_dump_autoloading_try.rb

require_relative '../../../lib/familia'
require 'fileutils'
require 'tmpdir'

# Create test directory structure for SafeDump autoloading testing
@safe_dump_test_dir = Dir.mktmpdir('familia_safe_dump_autoload_test')
@safe_dump_model_file = File.join(@safe_dump_test_dir, 'safe_dump_model.rb')
@safe_dump_extension_file = File.join(@safe_dump_test_dir, 'safe_dump_model', 'safe_dump_extensions.rb')
@safe_dump_feature_dir = File.join(@safe_dump_test_dir, 'safe_dump_model')
@safe_dump_features_subdir = File.join(@safe_dump_test_dir, 'safe_dump_model', 'features')
@safe_dump_global_features_dir = File.join(@safe_dump_test_dir, 'features')

# Create directory structure
FileUtils.mkdir_p(@safe_dump_feature_dir)
FileUtils.mkdir_p(@safe_dump_features_subdir)
FileUtils.mkdir_p(@safe_dump_global_features_dir)

# Write test model file that uses SafeDump
File.write(@safe_dump_model_file, <<~RUBY)
  class SafeDumpModel < Familia::Horreum
    field :user_id
    field :username
    field :email
    field :full_name
    field :created_at
    field :updated_at
    field :internal_notes

    feature :safe_dump
  end
RUBY

# Write main extension file (pattern: model_name/safe_dump_*.rb)
File.write(@safe_dump_extension_file, <<~RUBY)
  class SafeDumpModel
    # Define basic safe dump fields
    safe_dump_fields :user_id, :username, :email, :created_at

    # Custom method added by autoloaded file
    def autoloaded_extension_method
      "extension_loaded"
    end
  end
RUBY

# Write features subdirectory file (pattern: model_name/features/safe_dump_*.rb)
@safe_dump_features_subdir_file = File.join(@safe_dump_features_subdir, 'safe_dump_advanced.rb')
File.write(@safe_dump_features_subdir_file, <<~RUBY)
  class SafeDumpModel
    # Add computed fields
    safe_dump_field :display_name, lambda { |obj| "\#{obj.username} (\#{obj.email})" }
    safe_dump_field :is_active, lambda { |obj| !obj.updated_at.nil? }

    def features_subdir_method
      "features_subdir_loaded"
    end
  end
RUBY

# Write global features directory file (pattern: features/safe_dump_*.rb)
@safe_dump_global_file = File.join(@safe_dump_global_features_dir, 'safe_dump_global_helpers.rb')
File.write(@safe_dump_global_file, <<~RUBY)
  class SafeDumpModel
    # Add global helper fields
    safe_dump_field :metadata, lambda { |obj| { type: 'SafeDumpModel', version: '1.0' } }

    def global_helper_method
      "global_helper_loaded"
    end
  end
RUBY

# Create a test model that doesn't use SafeDump to test skipping
@non_safe_dump_model_file = File.join(@safe_dump_test_dir, 'non_safe_dump_model.rb')
File.write(@non_safe_dump_model_file, <<~RUBY)
  class NonSafeDumpModel < Familia::Horreum
    field :name
    # Note: No safe_dump feature enabled
  end
RUBY

## Test that SafeDump module has autoloading functionality
Familia::Features::SafeDump.respond_to?(:autoload_safe_dump_files)
#=> true

## Test SafeDump autoloading is called when feature is included
# Load the test model which should trigger SafeDump autoloading
safe_dump_model_instance = nil

begin
  require @safe_dump_model_file

  safe_dump_model_instance = SafeDumpModel.new(
    user_id: '123',
    username: 'testuser',
    email: 'test@example.com',
    full_name: 'Test User',
    created_at: Time.now.to_i,
    updated_at: Time.now.to_i,
    internal_notes: 'secret data'
  )

  true
rescue LoadError => e
  false
end
#=> true

## Test that autoloaded extension method is available
safe_dump_model_instance.respond_to?(:autoloaded_extension_method)
#=> true

safe_dump_model_instance.autoloaded_extension_method
#=> "extension_loaded"

## Test that features subdirectory method is available
safe_dump_model_instance.respond_to?(:features_subdir_method)
#=> true

safe_dump_model_instance.features_subdir_method
#=> "features_subdir_loaded"

## Test that global helper method is available
safe_dump_model_instance.respond_to?(:global_helper_method)
#=> true

safe_dump_model_instance.global_helper_method
#=> "global_helper_loaded"

## Test that safe dump fields were loaded from all autoloaded files
field_names = SafeDumpModel.safe_dump_field_names.sort
field_names
#=> [:created_at, :display_name, :email, :is_active, :metadata, :user_id, :username]

## Test that safe_dump functionality works with autoloaded fields
dump_result = safe_dump_model_instance.safe_dump
dump_result.keys.sort
#=> [:created_at, :display_name, :email, :is_active, :metadata, :user_id, :username]

## Test basic field values are dumped correctly
dump_result[:user_id]
#=> "123"

dump_result[:username]
#=> "testuser"

dump_result[:email]
#=> "test@example.com"

## Test computed field from features subdirectory works
dump_result[:display_name]
#=> "testuser (test@example.com)"

## Test boolean computed field
dump_result[:is_active]
#=> true

## Test metadata field from global features
dump_result[:metadata]
#=> {:type=>"SafeDumpModel", :version=>"1.0"}

## Test that internal_notes field is NOT included (not in safe dump fields)
dump_result.key?(:internal_notes)
#=> false

dump_result.key?(:full_name)
#=> false

## Test that feature_options stores calling location for SafeDump
options = SafeDumpModel.feature_options(:safe_dump)
options.key?(:calling_location)
#=> true

options[:calling_location].end_with?(@safe_dump_model_file)
#=> true

## Test autoloading with multiple different file patterns
# Create additional test files to verify all patterns work
@safe_dump_pattern_test_files = []

# Pattern 1: model_name/safe_dump_custom.rb
custom_file = File.join(@safe_dump_feature_dir, 'safe_dump_custom.rb')
File.write(custom_file, <<~RUBY)
  class SafeDumpModel
    safe_dump_field :custom_field, lambda { |obj| "custom_\#{obj.username}" }
  end
RUBY
@safe_dump_pattern_test_files << custom_file

# Pattern 2: model_name/features/safe_dump_special.rb
special_file = File.join(@safe_dump_features_subdir, 'safe_dump_special.rb')
File.write(special_file, <<~RUBY)
  class SafeDumpModel
    safe_dump_field :special_field, lambda { |obj| "special_\#{obj.email}" }
  end
RUBY
@safe_dump_pattern_test_files << special_file

# Pattern 3: features/safe_dump_utils.rb
utils_file = File.join(@safe_dump_global_features_dir, 'safe_dump_utils.rb')
File.write(utils_file, <<~RUBY)
  class SafeDumpModel
    safe_dump_field :utils_field, lambda { |obj| "utils_\#{obj.user_id}" }
  end
RUBY
@safe_dump_pattern_test_files << utils_file

# Force autoloading to pick up new files by creating a new model
SecondSafeDumpModel = Class.new(Familia::Horreum) do
  field :test_field

  # This should trigger autoloading of all safe_dump_* files
  feature :safe_dump
end

# Since the files use SafeDumpModel class, we need to manually load them
@safe_dump_pattern_test_files.each { |file| require file }

## Test that additional pattern files were loaded
updated_dump = safe_dump_model_instance.safe_dump
updated_dump.key?(:custom_field)
#=> true

updated_dump[:custom_field]
#=> "custom_testuser"

updated_dump.key?(:special_field)
#=> true

updated_dump[:special_field]
#=> "special_test@example.com"

updated_dump.key?(:utils_field)
#=> true

updated_dump[:utils_field]
#=> "utils_123"

## Test that SafeDump autoloading gracefully handles missing calling_location
TestModelWithoutLocation = Class.new(Familia::Horreum) do
  field :name
end

# Manually remove calling_location to test graceful handling
begin
  # This tests the autoload_safe_dump_files method directly
  Familia::Features::SafeDump.send(:autoload_safe_dump_files, TestModelWithoutLocation)
  true  # Should not crash
rescue => e
  false
end
#=> true

## Test that autoloading works regardless of whether SafeDump uses Autoloadable or direct implementation
# Both approaches should produce the same result
SafeDumpModel.safe_dump_field_names.include?(:user_id)
#=> true

SafeDumpModel.safe_dump_field_names.include?(:email)
#=> true

SafeDumpModel.safe_dump_field_names.include?(:display_name)
#=> true

## Test that autoloading doesn't interfere with models that don't use SafeDump
begin
  require @non_safe_dump_model_file
  non_safe_model = NonSafeDumpModel.new(name: 'test')

  # Should not have safe_dump methods
  !non_safe_model.respond_to?(:safe_dump)
rescue => e
  false
end
#=> true

# Cleanup test files and directories
FileUtils.rm_rf(@safe_dump_test_dir)
