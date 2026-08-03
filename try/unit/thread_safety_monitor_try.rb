# try/unit/thread_safety_monitor_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety monitoring tests
#
# Tests basic monitoring functionality without complex concurrency

# setup
Familia.stop_monitoring! if Familia.thread_safety_monitor.enabled
Familia.thread_safety_monitor.reset_metrics

## Monitor starts and stops correctly
Familia.start_monitoring!
started = Familia.thread_safety_monitor.enabled
Familia.stop_monitoring!
stopped = !Familia.thread_safety_monitor.enabled
started && stopped
#=> true

## Monitor tracks contentions
Familia.start_monitoring!
Familia.thread_safety_monitor.record_contention('test_location')
Familia.thread_safety_monitor.record_contention('test_location')
report = Familia.thread_safety_report
report[:summary][:mutex_contentions]
#=> 2

## Monitor tracks different locations
Familia.thread_safety_monitor.reset_metrics
Familia.thread_safety_monitor.record_contention('location_a')
Familia.thread_safety_monitor.record_contention('location_b')
Familia.thread_safety_monitor.record_contention('location_a')
report = Familia.thread_safety_report
report[:hot_spots].size
#=> 2

## Monitor tracks race conditions
Familia.thread_safety_monitor.reset_metrics
Familia.thread_safety_monitor.record_race_condition('test', 'details')
report = Familia.thread_safety_report
report[:summary][:race_detections]
#=> 1

## Monitor exports metrics
Familia.thread_safety_monitor.reset_metrics
Familia.thread_safety_monitor.record_contention('test')
metrics = Familia.thread_safety_metrics
metrics['familia.thread_safety.mutex_contentions']
#=> 1

## Health score starts at maximum
Familia.thread_safety_monitor.reset_metrics
report = Familia.thread_safety_report
report[:health]
#=> 100

## InstrumentedMutex is used for connection chain
conn_mutex = Familia.instance_variable_get(:@connection_chain_mutex)
conn_mutex.is_a?(Familia::ThreadSafety::InstrumentedMutex)
#=> true

## InstrumentedMutex tracks basic operations
mutex = Familia::ThreadSafety::InstrumentedMutex.new('test')
mutex.synchronize { 'work' }
stats = mutex.stats
stats[:lock_count]
#=> 1

## Monitor time_critical_section works
Familia.thread_safety_monitor.reset_metrics
result = Familia.thread_safety_monitor.time_critical_section('test') { 37 }
result
#=> 37

## Critical sections are tracked
report = Familia.thread_safety_report
report[:summary][:critical_sections]
#=> 1

## Monitor uses microsecond timing for precision
Familia.thread_safety_monitor.reset_metrics
start_μs = Familia.now_in_μs
Familia.thread_safety_monitor.time_critical_section('timing_test') do
  sleep 0.005  # 5ms sleep
end
end_μs = Familia.now_in_μs
duration_μs = end_μs - start_μs
# Should be at least 5000 microseconds (5ms)
duration_μs >= 5000
#=> true

## Wait time tracking uses microsecond precision
Familia.start_monitoring!
mutex = Familia::ThreadSafety::InstrumentedMutex.new('timing_mutex')
Familia.thread_safety_monitor.reset_metrics

# Force contention deterministically: t1 holds the mutex until t2 is
# provably blocked waiting on it. Contention is recorded as soon as the
# non-blocking try_lock inside #synchronize fails, so t2 attempting
# acquisition while t1 holds the lock guarantees contention_count > 0.
lock_held = Queue.new
release_lock = Queue.new

t1 = Thread.new do
  mutex.synchronize do
    lock_held.push(:held)
    release_lock.pop  # Hold the lock until explicitly released
  end
end

lock_held.pop  # Rendezvous: t1 definitely holds the mutex now

t2 = Thread.new { mutex.synchronize { 'got lock' } }
# Wait until t2 is blocked on the mutex (its try_lock has already failed
# and contention has been recorded by the time it sleeps in Mutex#lock).
# Bounded deadline so an unexpected t2 state fails the assertion below
# instead of hanging the suite.
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
Thread.pass while t2.alive? && t2.status != 'sleep' &&
                  Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline

release_lock.push(:go)
t1.join
t2.join

stats = mutex.stats
stats[:contention_count] > 0
#=> true

## Monitor preserves microsecond precision
Familia.thread_safety_monitor.reset_metrics
Familia.thread_safety_monitor.record_contention('precision_test', 1500)  # 1500μs = 1.5ms

report = Familia.thread_safety_report
hot_spot = report[:hot_spots].first
# Should preserve microsecond precision, not convert to seconds
hot_spot[:avg_wait_μs]
#=> 1500

## Critical section timing uses microseconds
Familia.thread_safety_monitor.reset_metrics
result = Familia.thread_safety_monitor.time_critical_section('precision_timing') do
  sleep 0.003  # 3ms
  37
end

report = Familia.thread_safety_report
section_perf = report[:section_performance].first
# Total time should be in microseconds (≥3000μs for 3ms sleep)
section_perf[:total_time_μs] >= 3000
#=> true

# teardown
Familia.stop_monitoring!
