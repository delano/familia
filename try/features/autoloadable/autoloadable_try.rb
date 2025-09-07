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
TestAutoloadableFeature.respond_to?(:post_inclusion_autoload)
#=> true

## Test that including autoloadable feature in Horreum class works
TestModelForAutoloadable.include(TestAutoloadableFeature)
TestModelForAutoloadable.ancestors.include?(TestAutoloadableFeature)
#=> true

## Test that post_inclusion_autoload can be called with test class
TestAutoloadableFeature.post_inclusion_autoload(TestModelForAutoloadable, :test_autoloadable_feature, {})
"success"
#=> "success"

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

## Test that SafeDump has post_inclusion_autoload capability
Familia::Features::SafeDump.respond_to?(:post_inclusion_autoload)
#=> true
