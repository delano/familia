# try/thread_safety/field_registration_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for field registration and collections
#
# Tests concurrent field definition to ensure that lazy initialization
# of @fields, @field_types, and @field_groups collections doesn't result
# in corruption or missing field definitions.
#
# These tests verify:
# 1. Concurrent field definitions on same class
# 2. Concurrent field group registrations
# 3. Concurrent DataType field registrations (list, set, zset, hashkey)
# 4. Field inheritance during concurrent subclass creation

## Concurrent field definitions on same class
class ConcurrentFieldModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(50)
field_names = Concurrent::Array.new

threads = 50.times.map do |i|
  Thread.new do
    barrier.wait
    field_name = "field_#{i}".to_sym
    ConcurrentFieldModel.field(field_name)
    field_names << field_name
  end
end

threads.each(&:join)
field_names.size
#=> 50

## Concurrent field group registrations
class GroupedFieldModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(20)
groups = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    field_name = "field_#{i}".to_sym
    GroupedFieldModel.field(field_name)
    groups << field_name
  end
end

threads.each(&:join)
groups.size
#=> 20

## Concurrent DataType field registrations (list, set, zset, hashkey)
class DataTypeFieldModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(40)
datatypes = Concurrent::Array.new

threads = 40.times.map do |i|
  Thread.new do
    barrier.wait
    case i % 4
    when 0
      DataTypeFieldModel.list("list_#{i}".to_sym)
      datatypes << :list
    when 1
      DataTypeFieldModel.set("set_#{i}".to_sym)
      datatypes << :set
    when 2
      DataTypeFieldModel.zset("zset_#{i}".to_sym)
      datatypes << :zset
    when 3
      DataTypeFieldModel.hashkey("hash_#{i}".to_sym)
      datatypes << :hashkey
    end
  end
end

threads.each(&:join)
datatypes.count(:list)
#=> 10

## Field type tracking during concurrent registration
class TypeTrackedModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(30)
field_types = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    field_name = "typed_field_#{i}".to_sym
    TypeTrackedModel.field(field_name)
    field_types << TypeTrackedModel.field_types[field_name]
  end
end

threads.each(&:join)
field_types.size
#=> 30

## Concurrent field definitions with default values
class DefaultValueModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(25)
defaults = Concurrent::Array.new

threads = 25.times.map do |i|
  Thread.new do
    barrier.wait
    field_name = "default_field_#{i}".to_sym
    DefaultValueModel.field(field_name)
    defaults << field_name
  end
end

threads.each(&:join)
defaults.size
#=> 25

## Field registration during object instantiation
class InstantiationModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
  field :name
  field :value
end

barrier = Concurrent::CyclicBarrier.new(30)
instances = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    obj = InstantiationModel.new(name: "obj_#{i}", value: i)
    instances << obj.name
  end
end

threads.each(&:join)
instances.size
#=> 30

## Concurrent class-level DataType registrations
class ClassDataTypeModel < Familia::Horreum
  identifier_field :test_id
  field :test_id

  def init
    @test_id ||= SecureRandom.hex(4)
  end
end

barrier = Concurrent::CyclicBarrier.new(20)
class_types = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    case i % 4
    when 0
      ClassDataTypeModel.class_list("class_list_#{i}".to_sym)
      class_types << :class_list
    when 1
      ClassDataTypeModel.class_set("class_set_#{i}".to_sym)
      class_types << :class_set
    when 2
      ClassDataTypeModel.class_zset("class_zset_#{i}".to_sym)
      class_types << :class_zset
    when 3
      ClassDataTypeModel.class_hashkey("class_hash_#{i}".to_sym)
      class_types << :class_hashkey
    end
  end
end

threads.each(&:join)
class_types.count(:class_list)
#=> 5
