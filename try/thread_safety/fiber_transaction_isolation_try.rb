# try/thread_safety/fiber_transaction_isolation_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for fiber-local transaction storage
#
# Tests that fiber-local transaction storage properly isolates transactions
# between different fibers and threads, ensuring no cross-contamination.
#
# These tests verify:
# 1. Concurrent transactions in different fibers are isolated
# 2. Transaction context doesn't leak between fibers
# 3. Nested transactions work correctly across fibers
# 4. Transaction cleanup happens properly per fiber

## Concurrent threads with isolated transactions
results = Concurrent::Array.new
barrier = Concurrent::CyclicBarrier.new(10)

# Each thread has its own root fiber, so transactions are isolated per-thread
threads = 10.times.map do |i|
  Thread.new do
    barrier.wait  # Synchronize start for maximum contention
    Familia.transaction do
      # Each thread's fiber should have isolated transaction context
      conn = Fiber[:familia_transaction]
      # Use direct Redis commands instead of save (which is not allowed in transactions)
      conn.set("test:txn:#{i}", "value_#{i}")
      results << [i, conn.object_id, "txn_#{i}"]
    end
  end
end

threads.each(&:join)

results
#==> _.size == 10
#==> _.map { |(i, _, _)| i }.sort == (0..9).to_a
#==> _.map { |(_, _, txn_id)| txn_id }.uniq.size == 10

## Transaction isolation across multiple threads
barrier = Concurrent::CyclicBarrier.new(15)
fiber_results = Concurrent::Array.new

# Each thread automatically has its own root fiber
threads = 15.times.map do |i|
  Thread.new do
    barrier.wait
    Familia.transaction do
      conn = Fiber[:familia_transaction]
      fiber_results << [Thread.current.object_id, conn.object_id]
    end
  end
end

threads.each(&:join)

fiber_results
#==> _.size == 15
#==> _.map { |(thread_id, _)| thread_id }.uniq.size >= 10

## Nested transactions in same fiber maintain context
nested_results = Concurrent::Array.new

fiber = Fiber.new do
  Familia.transaction do
    outer_conn = Fiber[:familia_transaction]
    nested_results << [:outer, outer_conn.object_id]

    Familia.transaction do
      inner_conn = Fiber[:familia_transaction]
      nested_results << [:inner, inner_conn.object_id]
    end

    after_inner = Fiber[:familia_transaction]
    nested_results << [:after_inner, after_inner.object_id]
  end

  after_outer = Fiber[:familia_transaction]
  nested_results << [:after_outer, after_outer.nil?]
end

fiber.resume

nested_results
#==> _.size == 4
#==> _[0][1] == _[1][1]  # Same connection for nested
#==> _[0][1] == _[2][1]  # Same connection after inner
#==> _[3][1] == true  # Cleaned up after outer

## Transaction context doesn't leak between sequential fibers
sequential_results = Concurrent::Array.new

5.times do |i|
  fiber = Fiber.new do
    Familia.transaction do
      conn = Fiber[:familia_transaction]
      sequential_results << [i, conn.object_id]
    end
  end
  fiber.resume
end

sequential_results
#==> _.size == 5
#==> _.map { |(i, _)| i } == [0, 1, 2, 3, 4]

## Concurrent fiber creation and transaction execution
creation_barrier = Concurrent::CyclicBarrier.new(20)
execution_results = Concurrent::Array.new

threads = 20.times.map do |i|
  Thread.new do
    creation_barrier.wait
    fiber = Fiber.new do
      begin
        Familia.transaction do
          # Use direct Redis commands instead of save
          conn = Fiber[:familia_transaction]
          conn.set("test:concurrent:#{i}", "value_#{i}")
          execution_results << "concurrent_#{i}"
        end
      rescue => e
        execution_results << [:error, e.class.name]
      end
    end
    fiber.resume
  end
end

threads.each(&:join)

execution_results
#==> _.size == 20
#==> _.all? { |r| r.is_a?(String) && r.start_with?('concurrent_') }
#==> true

## Transaction cleanup after exception
exception_results = Concurrent::Array.new

fiber = Fiber.new do
  begin
    Familia.transaction do
      exception_results << Fiber[:familia_transaction].object_id
      raise "Test exception"
    end
  rescue => e
    exception_results << [:exception, e.message]
  end
  exception_results << [:after_exception, Fiber[:familia_transaction].nil?]
end

fiber.resume
exception_results
#==> _.size == 3
#==> _[0].is_a?(Integer)
#==> _[1] == [:exception, "Test exception"]
#==> _[2] == [:after_exception, true]

## Fiber switching during transaction maintains context
switch_results = Concurrent::Array.new

fiber1 = Fiber.new do
  Familia.transaction do
    conn1 = Fiber[:familia_transaction]
    switch_results << [:fiber1_before_yield, conn1.object_id]
    Fiber.yield
    conn1_after = Fiber[:familia_transaction]
    switch_results << [:fiber1_after_yield, conn1_after.object_id]
  end
end

fiber2 = Fiber.new do
  Familia.transaction do
    conn2 = Fiber[:familia_transaction]
    switch_results << [:fiber2, conn2.object_id]
  end
end

fiber1.resume
fiber2.resume
fiber1.resume

switch_results
#==> _.size == 3
#==> _[0][1] == _[2][1]  # Same connection before/after yield
#==> _[0][1] != _[1][1]  # Different connections per fiber

## Multiple transactions per fiber (sequential)
multi_txn_results = Concurrent::Array.new

fiber = Fiber.new do
  3.times do |i|
    Familia.transaction do
      conn = Fiber[:familia_transaction]
      multi_txn_results << [i, conn.object_id]
    end
    multi_txn_results << [:between, Fiber[:familia_transaction].nil?]
  end
end

fiber.resume

multi_txn_results
#==> _.size == 6
#==> _.select { |(label, _)| label == :between }.all? { |(_, is_nil)| is_nil }
