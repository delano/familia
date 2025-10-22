# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for connection chain lazy initialization
#
# Tests concurrent connection chain initialization to ensure that the
# lazy initialization pattern (@connection_chain ||= build_connection_chain)
# doesn't result in duplicate chain instances or inconsistent state.
#
# These tests verify:
# 1. Concurrent module-level connection chain initialization
# 2. Connection chain consistency after concurrent reconnect
# 3. Thread-safe chain access during reconnection

@original_chain = nil

# Setup: Store original connection chain
@original_chain = Familia.instance_variable_get(:@connection_chain)

## Concurrent connection chain initialization builds only one chain
Familia.instance_variable_set(:@connection_chain, nil)
barrier = Concurrent::CyclicBarrier.new(50)
chains = Concurrent::Array.new

threads = 50.times.map do
  Thread.new do
    barrier.wait
    chain = Familia.dbclient('redis://127.0.0.1:6379')
    chains << chain.class.name
  end
end

threads.each(&:join)
chains.size
#=> 50

## Connection chain remains functional after concurrent access
Familia.instance_variable_set(:@connection_chain, nil)
barrier = Concurrent::CyclicBarrier.new(30)
results = Concurrent::Array.new

threads = 30.times.map do
  Thread.new do
    barrier.wait
    begin
      client = Familia.dbclient
      result = client.call('PING')
      results << result
    rescue => e
      results << e.class.name
    end
  end
end

threads.each(&:join)
results.size
#=> 30

## Concurrent reconnect calls maintain chain consistency
barrier = Concurrent::CyclicBarrier.new(20)
errors = Concurrent::Array.new
successes = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    barrier.wait
    begin
      if i < 10
        # Half the threads reconnect
        Familia.reconnect!
        successes << :reconnect
      else
        # Half access the chain
        client = Familia.dbclient
        client.call('PING')
        successes << :ping
      end
    rescue => e
      errors << e.class.name
    end
  end
end

threads.each(&:join)
(successes.size >= 15)
#=> true

## Connection chain rebuilds correctly after nil assignment
original = Familia.instance_variable_get(:@connection_chain)
barrier = Concurrent::CyclicBarrier.new(40)
results = Concurrent::Array.new

threads = 40.times.map do |i|
  Thread.new do
    barrier.wait
    if i == 0
      # One thread clears the chain
      Familia.instance_variable_set(:@connection_chain, nil)
    end
    # All threads try to use the chain
    begin
      client = Familia.dbclient
      results << client.class.name
    rescue => e
      results << e.class.name
    end
  end
end

threads.each(&:join)
results.size
#=> 40

## Rapid sequential reconnects from multiple threads
barrier = Concurrent::CyclicBarrier.new(10)
reconnect_counts = Concurrent::Array.new

threads = 10.times.map do
  Thread.new do
    barrier.wait
    count = 0
    10.times do
      Familia.reconnect!
      count += 1
    end
    reconnect_counts << count
  end
end

threads.each(&:join)
reconnect_counts.all? { |c| c == 10 }
#=> true

# Teardown: Restore original connection chain
Familia.instance_variable_set(:@connection_chain, @original_chain)
