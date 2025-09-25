# try/core/autoloader_try.rb

# Tests for Familia::Features::Autoloader
#
# TESTING STRATEGY:
# Autoloading is inherently tricky to test because:
# 1. Files are loaded once and cached by Ruby's require system
# 2. We need to simulate different directory structures
# 3. We need to verify that files are actually loaded (not just found)
#
# SOLUTION:
# Use temporary directories with Dir.mktmpdir to create isolated test
# environments and write test files that set global variables when
# loaded ($test_feature_loaded = true). Globals are reset before each
# test and FileUtils.rm_rf to clean up temp directories after each test.
#
# This approach allows us to:
# - Test actual file loading behavior (not just glob patterns) that verify
# the directory patterns that autoloader.included generates and also the
# exclusion logic works correctly.

require_relative '../../lib/familia'
require 'fileutils'
require 'tmpdir'

# SETUP: Create test directory structure for basic autoloader testing
# This simulates the lib/familia/features/ directory structure
@test_dir = Dir.mktmpdir('familia_autoloader_test')
@features_dir = File.join(@test_dir, 'features')
@test_file1 = File.join(@features_dir, 'test_feature1.rb')
@test_file2 = File.join(@features_dir, 'test_feature2.rb')
@excluded_file = File.join(@features_dir, 'autoloader.rb')

# Create directory structure
FileUtils.mkdir_p(@features_dir)

# Write test files
File.write(@test_file1, <<~RUBY)
  # Test feature file 1
  $test_feature1_loaded = true
RUBY

File.write(@test_file2, <<~RUBY)
  # Test feature file 2
  $test_feature2_loaded = true
RUBY

File.write(@excluded_file, <<~RUBY)
  # This should be excluded
  $autoloader_file_loaded = true
RUBY

## Test that Familia::Features::Autoloader exists and is a module
Familia::Features::Autoloader.is_a?(Module)
#=> true

## Test that autoload_files class method exists
Familia::Features::Autoloader.respond_to?(:autoload_files)
#=> true

## Test that included class method exists
Familia::Features::Autoloader.respond_to?(:included)
#=> true

## Test autoload_files with single pattern
$test_feature1_loaded = false
$test_feature2_loaded = false
$autoloader_file_loaded = false

Familia::Features::Autoloader.autoload_files(File.join(@features_dir, '*.rb'))
$test_feature1_loaded && $test_feature2_loaded
#=> true

## Test that autoload_files respects exclusions (using fresh files)
# Create a separate test environment to avoid conflicts with cached requires
@exclude_test_dir = Dir.mktmpdir('familia_autoloader_exclude_test')
@exclude_features_dir = File.join(@exclude_test_dir, 'features')
@include_file = File.join(@exclude_features_dir, 'include_me.rb')
@exclude_file = File.join(@exclude_features_dir, 'autoloader.rb')

FileUtils.mkdir_p(@exclude_features_dir)
File.write(@include_file, '$include_me_loaded = true')
File.write(@exclude_file, '$exclude_me_loaded = true')

$include_me_loaded = false
$exclude_me_loaded = false

Familia::Features::Autoloader.autoload_files(
  File.join(@exclude_features_dir, '*.rb'),
  exclude: ['autoloader.rb']
)

# Should load include file but not the excluded one
$include_me_loaded && !$exclude_me_loaded
#=> true

## Test autoload_files with array of patterns (using fresh files)
# Test that multiple glob patterns can be processed in a single call
@pattern_test_dir = Dir.mktmpdir('familia_autoloader_pattern_test')
@pattern_dir1 = File.join(@pattern_test_dir, 'dir1')
@pattern_dir2 = File.join(@pattern_test_dir, 'dir2')
@pattern_file1 = File.join(@pattern_dir1, 'file1.rb')
@pattern_file2 = File.join(@pattern_dir2, 'file2.rb')

FileUtils.mkdir_p(@pattern_dir1)
FileUtils.mkdir_p(@pattern_dir2)
File.write(@pattern_file1, '$pattern1_loaded = true')
File.write(@pattern_file2, '$pattern2_loaded = true')

$pattern1_loaded = false
$pattern2_loaded = false

Familia::Features::Autoloader.autoload_files([
  File.join(@pattern_dir1, '*.rb'),
  File.join(@pattern_dir2, '*.rb')
])

$pattern1_loaded && $pattern2_loaded
#=> true

## Test that included method loads features from features directory
# Create a mock module that includes Autoloader
@mock_features_module = Module.new do
  include Familia::Features::Autoloader
end

## The Features module already includes Autoloader, so test indirectly
Familia::Features.ancestors.include?(Familia::Features::Autoloader)
#=> true

## Test normalize_to_config_name method exists
# This method was added to fix issues with namespaced classes after commit d319d9d
# moved the namespace splitting logic from snake_case to config_name
Familia::Features::Autoloader.respond_to?(:normalize_to_config_name)
#=> true

## Test normalize_to_config_name with simple class name
Familia::Features::Autoloader.normalize_to_config_name('Customer')
#=> 'customer'

## Test normalize_to_config_name with PascalCase class name
Familia::Features::Autoloader.normalize_to_config_name('ApiTestUser')
#=> 'api_test_user'

## Test normalize_to_config_name with namespaced class name (single level)
Familia::Features::Autoloader.normalize_to_config_name('V2::Customer')
#=> 'customer'

## Test normalize_to_config_name with deeply namespaced class name
Familia::Features::Autoloader.normalize_to_config_name('My::Deep::Nested::Module::ApiTestUser')
#=> 'api_test_user'

## Test normalize_to_config_name with leading double colon
Familia::Features::Autoloader.normalize_to_config_name('::Customer')
#=> 'customer'

## Test normalize_to_config_name handles edge case with anonymous class representation
Familia::Features::Autoloader.normalize_to_config_name('#<Class:0x0001991a8>::ApiTestUser')
#=> 'api_test_user'

## Test that autoloader directory patterns work with namespaced classes
# This tests the core fix: ensuring that namespaced classes like TestNamespace::ApiTestModule
# correctly generate directory patterns using only the demodularized name (api_test_module)
# rather than the full namespaced name
# Create a test directory structure that simulates what would happen
# when a namespaced class includes the autoloader
@pattern_test_dir = Dir.mktmpdir('familia_autoloader_pattern_test')
@base_path = @pattern_test_dir
@config_name = 'api_test_module'  # This would be the result of normalize_to_config_name

# Create directory structure for different patterns
@features_global_dir = File.join(@base_path, 'features')
@features_config_dir = File.join(@base_path, @config_name, 'features')
@features_file = File.join(@base_path, @config_name, 'features.rb')

FileUtils.mkdir_p(@features_global_dir)
FileUtils.mkdir_p(@features_config_dir)

# Write test files for each pattern
@global_feature = File.join(@features_global_dir, 'global_feature.rb')
@config_feature = File.join(@features_config_dir, 'config_feature.rb')

File.write(@global_feature, '$global_feature_loaded = true')
File.write(@config_feature, '$config_feature_loaded = true')
File.write(@features_file, '$features_file_loaded = true')

# These are the exact patterns that autoloader.included generates:
# 1. Global features dir: base_path/features/*.rb
# 2. Config-specific features dir: base_path/config_name/features/*.rb
# 3. Config-specific features file: base_path/config_name/features.rb
@dir_patterns = [
  File.join(@base_path, 'features', '*.rb'),
  File.join(@base_path, @config_name, 'features', '*.rb'),
  File.join(@base_path, @config_name, 'features.rb'),
]
# Verify all three patterns are correctly constructed
@dir_patterns.length
#=> 3

# Reset test flags - critical for testing actual file loading behavior
$global_feature_loaded = false
$config_feature_loaded = false
$features_file_loaded = false

## Test that global features pattern matches correctly
Dir.glob(@dir_patterns[0]).length
#=> 1

## Test that config-specific features pattern matches correctly
Dir.glob(@dir_patterns[1]).length
#=> 1

## Test that config-specific features.rb file exists
File.exist?(@dir_patterns[2])
#=> true

## Test loading all patterns simulates autoloader.included behavior
# This simulates what happens when a class includes Familia::Features::Autoloader
# All three file patterns should be processed and their contents loaded
Familia::Features::Autoloader.autoload_files(@dir_patterns)

# Verify all three test files were actually loaded (not just found)
$global_feature_loaded && $config_feature_loaded && $features_file_loaded
#=> true

# Cleanup test files and directories
FileUtils.rm_rf(@test_dir)
FileUtils.rm_rf(@exclude_test_dir)
FileUtils.rm_rf(@pattern_test_dir)
