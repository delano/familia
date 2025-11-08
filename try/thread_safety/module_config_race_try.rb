# try/thread_safety/module_config_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for module-level configuration state
#
# Tests concurrent modification of Familia module configuration to ensure
# that race conditions don't cause inconsistent behavior or invalid state.
#
# These tests verify:
# 1. Concurrent URI configuration changes
# 2. Concurrent prefix/suffix configuration
# 3. Concurrent delimiter configuration during key generation
# 4. Configuration consistency across threads

@original_uri = nil
@original_prefix = nil
@original_suffix = nil
@original_delim = nil

# Setup: Store original configuration
@original_uri = Familia.uri
@original_prefix = Familia.prefix
@original_suffix = Familia.suffix
@original_delim = Familia.delim

## Concurrent URI configuration changes result in valid state
barrier = Concurrent::CyclicBarrier.new(20)
uris = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    new_uri = "redis://localhost:#{6379 + i}"
    Familia.uri = new_uri
    uris << Familia.uri.to_s
  end
end

threads.each(&:join)
uris.size
#=> 20

## Concurrent prefix configuration maintains valid state
Familia.prefix = nil
barrier = Concurrent::CyclicBarrier.new(30)
prefixes = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    Familia.prefix = "prefix_#{i}"
    prefixes << Familia.prefix
  end
end

threads.each(&:join)
prefixes.size
#=> 30

## Concurrent suffix configuration maintains valid state
Familia.suffix = :object
barrier = Concurrent::CyclicBarrier.new(30)
suffixes = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    Familia.suffix = "suffix_#{i}".to_sym
    suffixes << Familia.suffix
  end
end

threads.each(&:join)
suffixes.size
#=> 30

## Concurrent delimiter configuration during key generation
class DelimiterTestModel < Familia::Horreum
  identifier_field :test_id
  field :test_id
  field :value
end

Familia.delim = ':'
barrier = Concurrent::CyclicBarrier.new(30)
keys = Concurrent::Array.new

threads = 30.times.map do |i|
  Thread.new do
    barrier.wait
    if i % 3 == 0
      Familia.delim = '::'
    end
    obj = DelimiterTestModel.new(test_id: "id_#{i}", value: "test")
    keys << obj.dbkey
  end
end

threads.each(&:join)
keys.size
#=> 30

## Concurrent prefix and suffix changes together
Familia.prefix = nil
Familia.suffix = :object
barrier = Concurrent::CyclicBarrier.new(50)
configs = Concurrent::Array.new

threads = 50.times.map do |i|
  Thread.new do
    barrier.wait
    if i.even?
      Familia.prefix = "prefix_#{i}"
    else
      Familia.suffix = "suffix_#{i}"
    end
    configs << [Familia.prefix, Familia.suffix]
  end
end

threads.each(&:join)
configs.size
#=> 50

## Configuration reads during concurrent writes are consistent
Familia.prefix = 'test'
barrier = Concurrent::CyclicBarrier.new(40)
read_results = Concurrent::Array.new

threads = 40.times.map do |i|
  Thread.new do
    barrier.wait
    if i < 5
      # A few threads write
      Familia.prefix = "new_prefix_#{i}"
    else
      # Most threads read
      read_results << Familia.prefix
    end
  end
end

threads.each(&:join)
read_results.size
#=> 35

## Concurrent URI and connection provider changes
@original_provider = Familia.connection_provider
barrier = Concurrent::CyclicBarrier.new(20)
results = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    if i.even?
      Familia.uri = "redis://localhost:#{6379 + i}"
    else
      results << Familia.uri.to_s
    end
  end
end

threads.each(&:join)
results.size
#=> 10

# Teardown: Restore original configuration
Familia.connection_provider = @original_provider
Familia.uri = @original_uri
Familia.prefix = @original_prefix
Familia.suffix = @original_suffix
Familia.delim = @original_delim
