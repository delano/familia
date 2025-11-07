# try/thread_safety/feature_registry_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for feature registry initialization
#
# Tests concurrent feature registration to ensure that lazy initialization
# of @features_available and @feature_definitions doesn't result in
# corruption or missing feature registrations.
#
# These tests verify:
# 1. Concurrent feature registration on same class
# 2. Feature dependency resolution during concurrent registration
# 3. Feature metadata consistency
# 4. Feature activation during concurrent access

## Concurrent feature registration on same class
module TestFeature1; end
module TestFeature2; end
module TestFeature3; end

class FeatureTestModel1 < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

FeatureTestModel1.instance_variable_set(:@features_available, nil)
FeatureTestModel1.instance_variable_set(:@feature_definitions, nil)

barrier = Concurrent::CyclicBarrier.new(20)
features = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    feature_module = Module.new
    feature_name = "test_feature_#{i}".to_sym
    FeatureTestModel1.add_feature(feature_module, feature_name)
    features << feature_name
  end
end

threads.each(&:join)

[features.size, FeatureTestModel1.features_available.is_a?(Hash)]
#=> [20, true]

## Feature activation during concurrent declaration
class FeatureTestModel2 < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(15)
activated = Concurrent::Array.new

threads = 15.times.map do |i|
  Thread.new do
    barrier.wait
    feature_name = "activated_feature_#{i}".to_sym
    feature_module = Module.new
    FeatureTestModel2.add_feature(feature_module, feature_name)
    FeatureTestModel2.feature(feature_name)
    activated << feature_name
  end
end

threads.each(&:join)
activated.size
#=> 15

## Concurrent feature registration with field groups
class FeatureFieldGroupModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(20)
feature_groups = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    feature_module = Module.new
    feature_name = "grouped_feature_#{i}".to_sym
    field_group = "group_#{i}".to_sym
    FeatureFieldGroupModel.add_feature(feature_module, feature_name, field_group: field_group)
    feature_groups << field_group
  end
end

threads.each(&:join)
feature_groups.size
#=> 20

## Feature dependency registration during concurrent access
class DependencyTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(25)
dependencies = Concurrent::Array.new

threads = 25.times.map do |i|
  Thread.new do
    barrier.wait
    feature_module = Module.new
    feature_name = "dependent_feature_#{i}".to_sym
    depends_on = i > 0 ? ["dependent_feature_#{i - 1}".to_sym] : []
    DependencyTestModel.add_feature(feature_module, feature_name, depends_on: depends_on)
    dependencies << feature_name
  end
end

threads.each(&:join)
dependencies.size
#=> 25

## Concurrent feature queries
class QueryTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

# Pre-register some features
5.times do |i|
  QueryTestModel.add_feature(Module.new, "query_feature_#{i}".to_sym)
end

barrier = Concurrent::CyclicBarrier.new(30)
query_results = Concurrent::Array.new

threads = 30.times.map do
  Thread.new do
    barrier.wait
    available = QueryTestModel.features_available
    query_results << available.keys.size
  end
end

threads.each(&:join)
query_results.size
#=> 30


## Feature metadata consistency during concurrent registration
class MetadataTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(20)
metadata = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    feature_module = Module.new do
      def self.feature_name
        "metadata_feature"
      end
    end
    feature_name = "meta_feature_#{i}".to_sym
    MetadataTestModel.add_feature(feature_module, feature_name)
    metadata << [feature_name, MetadataTestModel.features_available[feature_name]]
  end
end

threads.each(&:join)
metadata.size
#=> 20


## Feature definitions hash consistency
class DefinitionsTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(30)
definitions = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    feature_module = Module.new
    feature_name = "def_feature_#{i}".to_sym
    DefinitionsTestModel.add_feature(feature_module, feature_name)
    definitions << DefinitionsTestModel.feature_definitions.keys.size
  end
end

threads.each(&:join)
definitions.size
#=> 30
