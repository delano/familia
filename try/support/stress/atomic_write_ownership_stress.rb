#!/usr/bin/env ruby
# try/support/stress/atomic_write_ownership_stress.rb
#
# frozen_string_literal: true

# Probabilistic stress test for atomic_write ownership CAS guard.
#
# NOT run in CI (lives outside the try/*_try.rb auto-discovery pattern).
# Run manually:
#   bundle exec ruby try/support/stress/atomic_write_ownership_stress.rb
#
# This test hammers the OWNER_STATE_MUTEX guard with N threads released
# simultaneously via a CyclicBarrier. On MRI the GVL serialises bytecode,
# so exact winner counts vary with scheduling; on JRuby/TruffleRuby the
# race is real every iteration.
#
# Schedule-invariant assertions (always hold regardless of timing):
#   - No unexpected exceptions (only OperationModeError with correct message)
#   - winners + rejections == threads_per_iteration (conservation)
#   - Every persisted winner is well-formed ("thread_N" pattern)
#   - Every marks set has >= 1 well-formed member
#   - No data corruption (winner value matches the thread_N pattern)

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

class CASStressPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :winner
  set :marks
end

CASStressPlan.instances.clear rescue nil
CASStressPlan.all.each(&:destroy!) rescue nil

ITERATIONS = Integer(ENV.fetch('STRESS_ITERATIONS', '100'))
THREADS_PER_ITERATION = Integer(ENV.fetch('STRESS_THREADS', '10'))

success_counter = Concurrent::AtomicFixnum.new(0)
raise_counter = Concurrent::AtomicFixnum.new(0)
unexpected_errors = Concurrent::Array.new
winner_values = Concurrent::Array.new
conservation_violations = Concurrent::Array.new

ITERATIONS.times do |iter|
  plan = CASStressPlan.new(planid: "stress_#{iter}", winner: 'initial')
  plan.save

  barrier = Concurrent::CyclicBarrier.new(THREADS_PER_ITERATION)
  iter_successes = Concurrent::AtomicFixnum.new(0)
  iter_rejections = Concurrent::AtomicFixnum.new(0)

  threads = THREADS_PER_ITERATION.times.map do |tid|
    Thread.new do
      barrier.wait
      begin
        plan.atomic_write do
          plan.winner = "thread_#{tid}"
          plan.marks.add("mark_#{tid}")
        end
        iter_successes.increment
        success_counter.increment
      rescue Familia::OperationModeError => e
        if e.message.include?('another Fiber or Thread')
          iter_rejections.increment
          raise_counter.increment
        else
          unexpected_errors << [:wrong_message, iter, e.message]
        end
      rescue => e
        unexpected_errors << [:wrong_class, iter, e.class.name, e.message]
      end
    end
  end

  threads.each(&:join)

  total = iter_successes.value + iter_rejections.value
  if total != THREADS_PER_ITERATION
    conservation_violations << [iter, iter_successes.value, iter_rejections.value]
  end

  reloaded = CASStressPlan.find_by_id("stress_#{iter}")
  winner_values << reloaded.winner if reloaded
end

# Report
puts "=" * 60
puts "Atomic Write Ownership Stress Test"
puts "=" * 60
puts "Iterations:          #{ITERATIONS}"
puts "Threads/iteration:   #{THREADS_PER_ITERATION}"
puts "Total winners:       #{success_counter.value}"
puts "Total rejections:    #{raise_counter.value}"
puts "Unexpected errors:   #{unexpected_errors.size}"
puts "Conservation errors: #{conservation_violations.size}"
puts

# Assertions
pass = true

if unexpected_errors.any?
  puts "FAIL: Unexpected errors:"
  unexpected_errors.each { |e| puts "  #{e.inspect}" }
  pass = false
end

if conservation_violations.any?
  puts "FAIL: Conservation violations (winners + rejections != #{THREADS_PER_ITERATION}):"
  conservation_violations.each { |v| puts "  iteration=#{v[0]} wins=#{v[1]} rejects=#{v[2]}" }
  pass = false
end

malformed = winner_values.reject { |w| w.match?(/\Athread_\d+\z/) }
if malformed.any?
  puts "FAIL: Malformed winner values: #{malformed.inspect}"
  pass = false
end

marks_problems = []
ITERATIONS.times do |iter|
  reloaded = CASStressPlan.find_by_id("stress_#{iter}")
  next unless reloaded
  members = reloaded.marks.members
  if members.empty?
    marks_problems << [iter, 'empty marks set']
  elsif members.any? { |m| !m.match?(/\Amark_\d+\z/) }
    marks_problems << [iter, "malformed marks: #{members.inspect}"]
  end
end

if marks_problems.any?
  puts "FAIL: Marks problems:"
  marks_problems.each { |p| puts "  #{p.inspect}" }
  pass = false
end

if pass
  puts "PASS: All schedule-invariant assertions hold."
  puts "  (#{success_counter.value} winners across #{ITERATIONS} iterations is"
  puts "   expected to vary with GVL scheduling — this is NOT a failure.)"
else
  puts "\nSome assertions failed. See above."
end

# Teardown
CASStressPlan.instances.clear rescue nil
CASStressPlan.all.each(&:destroy!) rescue nil

exit(pass ? 0 : 1)
