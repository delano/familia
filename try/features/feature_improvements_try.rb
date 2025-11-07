# try/features/feature_improvements_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Test hierarchical feature registration
class ::TestClass
  include Familia::Base
end

class TestSubClass < TestClass
end

# Create a simple test feature
module ::TestFeature
  def test_method
    "test feature working"
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def class_test_method
      "class method from feature"
    end
  end
end

# Test SafeDump DSL improvements
class ::TestModelWithSafeDump
  include Familia::Base
  include Familia::Features::SafeDump

  attr_accessor :id, :name, :email, :active

  def initialize(attrs = {})
    attrs.each { |k, v| send("#{k}=", v) }
  end

  def active?
    @active == true
  end

  # Define safe dump fields using new DSL
  safe_dump_field :id
  safe_dump_field :name
  safe_dump_field :status, ->(obj) { obj.active? ? 'active' : 'inactive' }
  safe_dump_field :email
  safe_dump_field :computed_field, ->(obj) { "#{obj.name}-computed" }
end

# Test field definitions in feature modules
module ::TestFieldFeature
  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
    # This should work - field calls in ClassMethods should execute in the extending class context
    def define_test_fields
      # Assuming we have a field method available (this would come from Horreum)
      # For this test, we'll just verify the method gets called in the right context
      self.name + "_with_fields"
    end
  end
end

class ::TestFieldClass
  include Familia::Base
  include TestFieldFeature
end

## Test model-specific feature registration
# Register feature on TestClass
TestClass.add_feature TestFeature, :test_feature
#=> TestFeature

## TestClass should have the feature available
TestClass.features_available[:test_feature]
#=> TestFeature

## TestSubClass should inherit the feature from TestClass via ancestry chain
TestSubClass.find_feature(:test_feature)
#=> TestFeature

## Familia::Base should also be able to find features in the chain
Familia::Base.find_feature(:test_feature, TestSubClass)
#=> TestFeature

## Check that fields were registered correctly
TestModelWithSafeDump.safe_dump_field_names.sort
#=> [:computed_field, :email, :id, :name, :status]

## Test the safe_dump functionality
@test_model = TestModelWithSafeDump.new
@test_model.id = 123
@test_model.name = "Test User"
@test_model.email = "test@example.com"
@test_model.active = true

@result = @test_model.safe_dump
#=:> Hash

## Test safe_dump returns correct values
@result[:id]
#=> 123

## Test safe_dump name field
@result[:name]
#=> "Test User"

## Test safe_dump email field
@result[:email]
#=> "test@example.com"

## Test safe_dump status field with callable
@result[:status]
#=> "active"

## Test safe_dump computed field
@result[:computed_field]
#=> "Test User-computed"

## Test that ClassMethods execute in the right context
TestFieldClass.define_test_fields
#=> "TestFieldClass_with_fields"
