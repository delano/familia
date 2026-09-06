# try/thread_safety/instrumented_mutex_exclusion_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# InstrumentedMutex must exclude even when monitoring is disabled.
#
# Monitoring is off by default. An earlier InstrumentedMutex#synchronize
# returned `yield` on that path without taking the lock, which silently
# turned every InstrumentedMutex in the library (connection chain, field
# registration, related_fields_mutex) into a no-op outside a monitoring
# session. These cases hold only when the underlying Mutex is actually
# acquired on the disabled path: overlapping holders and lost increments
# appear immediately otherwise.

Familia.stop_monitoring! if Familia.thread_safety_monitor.enabled

# Runs +threads_n+ threads through +mutex.synchronize+, each incrementing a
# shared counter +iterations+ times with deliberate yield points inside the
# critical section. Returns [max concurrent holders, final counter].
def rfl428_exclusion_probe(mutex, threads_n: 8, iterations: 200)
  counter = 0
  holders = 0
  max_holders = 0
  barrier = Concurrent::CyclicBarrier.new(threads_n)
  threads = threads_n.times.map do
    Thread.new do
      barrier.wait
      iterations.times do
        mutex.synchronize do
          holders += 1
          max_holders = holders if holders > max_holders
          Thread.pass
          snapshot = counter
          Thread.pass
          sleep 0
          counter = snapshot + 1
          holders -= 1
        end
      end
    end
  end
  threads.each(&:join)
  [max_holders, counter]
end

@mutex = Familia::ThreadSafety::InstrumentedMutex.new('rfl428_test')

## Monitoring is disabled for this file (the default; that is the path under test)
Familia.thread_safety_monitor.enabled
#=> false

## With monitoring disabled, no two threads are ever inside synchronize at once and no increment is lost
rfl428_exclusion_probe(@mutex)
#=> [1, 1600]

## With monitoring disabled, synchronize still returns the block's value
@mutex.synchronize { :held }
#=> :held

## With monitoring disabled, the lock is held (and owned) inside the block and released after
inside = @mutex.synchronize { [@mutex.locked?, @mutex.owned?] }
[inside, @mutex.locked?]
#=> [[true, true], false]

## With monitoring disabled, the lock is released when the block raises
begin
  @mutex.synchronize { raise 'boom' }
rescue RuntimeError
end
@mutex.locked?
#=> false

## With monitoring disabled, synchronize is non-reentrant (what initialize_relatives relies on)
@mutex.synchronize { @mutex.synchronize { :never } }
#=!> ThreadError
#=~> /deadlock; recursive locking/

## With monitoring enabled, the instrumented path excludes too
Familia.start_monitoring!
result = rfl428_exclusion_probe(Familia::ThreadSafety::InstrumentedMutex.new('rfl428_monitored'))
Familia.stop_monitoring!
result
#=> [1, 1600]

# teardown
Familia.stop_monitoring! if Familia.thread_safety_monitor.enabled
