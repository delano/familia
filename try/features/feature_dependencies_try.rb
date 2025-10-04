# try/features/feature_dependencies_try.rb

require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Create test features with dependencies for testing
module TestFeatureA
  def self.included(base)
    Familia.trace :included, base, self if Familia.debug?
    base.extend ClassMethods
  end

  module ClassMethods
    def test_feature_a_method
      "feature_a_active"
    end
  end

  def test_feature_a_instance
    "instance_feature_a"
  end
end

module TestFeatureB
  def self.included(base)
    Familia.trace :INCLUDED, base, self if Familia.debug?
    base.extend ClassMethods
  end

  module ClassMethods
    def test_feature_b_method
      "feature_b_active"
    end
  end

  def test_feature_b_instance
    "instance_feature_b"
  end
end

module TestFeatureCWithDeps
  def self.included(base)
    Familia.trace :feature_load, base, self if Familia.debug?
    base.extend ClassMethods
  end

  module ClassMethods
    def test_feature_c_method
      "feature_c_with_deps_active"
    end
  end

  def test_feature_c_instance
    "instance_feature_c_with_deps"
  end
end

# Register test features manually
Familia::Base.add_feature TestFeatureA, :test_feature_a
Familia::Base.add_feature TestFeatureB, :test_feature_b
Familia::Base.add_feature TestFeatureCWithDeps, :test_feature_c, depends_on: [:test_feature_a, :test_feature_b]

## Feature definitions are created correctly
Familia::Base.feature_definitions.key?(:test_feature_a)
#=> true

## Feature definitions store dependencies correctly
Familia::Base.feature_definitions[:test_feature_c].depends_on
#=> [:test_feature_a, :test_feature_b]

## Features without dependencies have empty depends_on array
Familia::Base.feature_definitions[:test_feature_a].depends_on
#=> []

## Feature definitions store name correctly
Familia::Base.feature_definitions[:test_feature_c].name
#=> :test_feature_c

## Successfully enable feature without dependencies
class NoDepsTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :test_feature_a
end
@nodeps = NoDepsTest.new(id: 'test1')
@nodeps.test_feature_a_instance
#=> "instance_feature_a"

## Successfully enable multiple features in correct order
class MultiFeatureTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :test_feature_a
  feature :test_feature_b
  feature :test_feature_c
end
@multitest = MultiFeatureTest.new(id: 'test2')
@multitest.test_feature_c_instance
#=> "instance_feature_c_with_deps"

## Class methods from dependent features are available
MultiFeatureTest.test_feature_c_method
#=> "feature_c_with_deps_active"

## All prerequisite features are available in features_enabled
MultiFeatureTest.features_enabled.include?(:test_feature_a)
#=> true

## All prerequisite features are available
MultiFeatureTest.features_enabled.include?(:test_feature_b)
#=> true

## Dependent feature is available
MultiFeatureTest.features_enabled.include?(:test_feature_c)
#=> true

## Feature dependency validation fails when dependencies missing
class MissingDepsTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :test_feature_c  # Missing dependencies should cause error
end
#=!> Familia::Problem

## Partial dependencies cause validation failure
class PartialDepsTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :test_feature_a  # Only one of two required dependencies
  feature :test_feature_c
end
#=!> Familia::Problem

## Invalid feature name raises appropriate error
class InvalidFeatureTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :nonexistent_feature
end
#=!> Familia::Problem

## Duplicate feature inclusion gives warning but continues
class DuplicateFeatureTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :test_feature_a
  feature :test_feature_a  # Duplicate should warn
end
@duplicate_test = DuplicateFeatureTest.new(id: 'dup1')
@duplicate_test.test_feature_a_instance
#=> "instance_feature_a"

@nodeps.destroy! rescue nil
@multitest.destroy! rescue nil
@duplicate_test.destroy! rescue nil
@nodeps = nil
@multitest = nil
@duplicate_test = nil
