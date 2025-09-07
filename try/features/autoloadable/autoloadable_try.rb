# try/features/autoloadable/autoloadable_try.rb

require_relative '../../../lib/familia'

# Create test feature module that includes Autoloadable
module TestAutoloadableFeature
  include Familia::Features::Autoloadable

  def self.included(base)
    super
    base.define_method(:test_feature_method) { "feature_loaded" }
  end
end

# Create test class to include the feature
class TestModelForAutoloadable < Familia::Horreum
  field :name
end

## Test that Autoloadable can be included in feature modules
TestAutoloadableFeature.ancestors.include?(Familia::Features::Autoloadable)
#=> true

## Test that Autoloadable extends feature modules with ClassMethods
TestAutoloadableFeature.respond_to?(:calling_location)
#=> true

## Test that calling_location is initially nil
TestAutoloadableFeature.calling_location.nil?
#=> true

## Test that including autoloadable feature in Horreum class works
TestModelForAutoloadable.include(TestAutoloadableFeature)
TestModelForAutoloadable.ancestors.include?(TestAutoloadableFeature)
#=> true

## Test that calling_location is set when feature is included
TestAutoloadableFeature.calling_location.nil?
#=> false

## Test that calling_location is a string path
TestAutoloadableFeature.calling_location.is_a?(String)
#=> true

## Test that calling_location points to this test file
TestAutoloadableFeature.calling_location.end_with?('autoloadable_try.rb')
#=> true

## Test that feature methods are available on the model
@test_instance = TestModelForAutoloadable.new(name: 'test')
@test_instance.respond_to?(:test_feature_method)
#=> true

## Test that feature method works
@test_instance.test_feature_method
#=> "feature_loaded"

## Test that Autoloadable works with DataType classes (should not crash)
class TestDataTypeAutoloadable < Familia::DataType
  include Familia::Features::Autoloadable
end

TestDataTypeAutoloadable.ancestors.include?(Familia::Features::Autoloadable)
#=> true

## Test that SafeDump includes Autoloadable (real-world usage)
Familia::Features::SafeDump.ancestors.include?(Familia::Features::Autoloadable)
#=> true

## Test that SafeDump has calling_location tracking capability
Familia::Features::SafeDump.respond_to?(:calling_location)
#=> true
