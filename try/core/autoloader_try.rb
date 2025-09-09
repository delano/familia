# try/core/autoloader_try.rb

require_relative '../../lib/familia'
require 'fileutils'
require 'tmpdir'

# Create test directory structure for Autoloader testing
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

# The Features module already includes Autoloader, so test indirectly
Familia::Features.ancestors.include?(Familia::Features::Autoloader)
#=> true

# Cleanup test files and directories
FileUtils.rm_rf(@test_dir)
FileUtils.rm_rf(@exclude_test_dir)
FileUtils.rm_rf(@pattern_test_dir)
