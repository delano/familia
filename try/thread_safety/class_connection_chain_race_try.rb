# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for class-level connection chain initialization
#
# Tests concurrent class-level connection chain initialization to ensure
# that each Horreum subclass properly initializes its own connection chain
# without race conditions or shared state issues.
#
# These tests verify:
# 1. Concurrent class-level connection chain initialization
# 2. Multiple model classes initialized concurrently
# 3. Inheritance chain with concurrent access
# 4. Connection chain isolation between classes

## Concurrent class-level connection chain initialization
class TestModel1 < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :name
end

TestModel1.instance_variable_set(:@class_connection_chain, nil)
barrier = Concurrent::CyclicBarrier.new(50)
chains = Concurrent::Array.new

threads = 50.times.map do
  Thread.new do
    barrier.wait
    client = TestModel1.dbclient
    # Store the actual connection chain object ID to detect singleton violations
    chains << TestModel1.instance_variable_get(:@connection_chain).object_id
  end
end

threads.each(&:join)
# Test multiple invariants (pattern from middleware tests):
# - No nil entries (corruption check)
# - All chains are same object (singleton property)
# - Got expected number of results
[chains.any?(nil), chains.uniq.size, chains.size]
#=> [false, 1, 50]


## Multiple model classes initialized concurrently
barrier = Concurrent::CyclicBarrier.new(10)
models = Concurrent::Array.new

threads = 10.times.map do |i|
  Thread.new do
    model_class = Class.new(Familia::Horreum) do
      def self.name
        "ConcurrentTestModel#{Thread.current.object_id}"
      end

      identifier_field :test_id
      field :test_id
      field :value

      def init
        @test_id ||= SecureRandom.hex(4)
      end
    end

    barrier.wait
    client = model_class.dbclient
    models << [model_class.name, client.class.name]
  end
end

threads.each(&:join)
models.size
#=> 10


## Connection chain per-class isolation
class TestModel2 < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :name
end

class TestModel3 < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :name
end

TestModel2.instance_variable_set(:@class_connection_chain, nil)
TestModel3.instance_variable_set(:@class_connection_chain, nil)

barrier = Concurrent::CyclicBarrier.new(20)
results = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    if i.even?
      client = TestModel2.dbclient
      results << [:model2, client.class.name]
    else
      client = TestModel3.dbclient
      results << [:model3, client.class.name]
    end
  end
end

threads.each(&:join)
results.size
#=> 20


## Inheritance chain with concurrent access
class BaseModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :base_field
end

class ChildModel1 < BaseModel
  field :child_field
end

class ChildModel2 < BaseModel
  field :other_field
end

ChildModel1.instance_variable_set(:@class_connection_chain, nil)
ChildModel2.instance_variable_set(:@class_connection_chain, nil)

barrier = Concurrent::CyclicBarrier.new(30)
chains = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    case i % 3
    when 0
      client = BaseModel.dbclient
      chains << [:base, client.class.name]
    when 1
      client = ChildModel1.dbclient
      chains << [:child1, client.class.name]
    when 2
      client = ChildModel2.dbclient
      chains << [:child2, client.class.name]
    end
  end
end

threads.each(&:join)
chains.size
#=> 30

## Concurrent database operations through class connection chain
class OperationTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id
  field :value
end

barrier = Concurrent::CyclicBarrier.new(25)
results = Concurrent::Array.new

threads = 25.times.map do |i|
  Thread.new do
    barrier.wait
    obj = OperationTestModel.new(test_id: "test_#{i}", value: i)
    obj.save
    results << obj.test_id
  end
end

threads.each(&:join)
results.size
#=> 25

## Class connection chain rebuilds after reconnect
class ReconnectTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :name
end

ReconnectTestModel.instance_variable_set(:@class_connection_chain, nil)
barrier = Concurrent::CyclicBarrier.new(20)
results = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    if i < 5
      # Some threads trigger reconnect
      Familia.reconnect!
    end
    # All threads access the chain
    client = ReconnectTestModel.dbclient
    results << client.class.name
  end
end

threads.each(&:join)
results.size
#=> 20


## Rapid sequential access to class connection chain
class RapidAccessModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :value
end

barrier = Concurrent::CyclicBarrier.new(15)
access_counts = Concurrent::Array.new

threads = 15.times.map do
  Thread.new do
    barrier.wait
    count = 0
    20.times do
      RapidAccessModel.dbclient
      count += 1
    end
    access_counts << count
  end
end

threads.each(&:join)
access_counts.size
#=> 15
