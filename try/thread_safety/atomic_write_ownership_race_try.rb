# try/thread_safety/atomic_write_ownership_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Thread safety tests for acquire_atomic_write_ownership! compare-and-swap.
#
# lib/familia/horreum/atomic_write.rb wraps the @atomic_write_owner ivar
# check-then-set in OWNER_STATE_MUTEX.synchronize. Without that mutex,
# two threads could both observe a nil owner and simultaneously claim
# ownership, then open parallel MULTIs against shared scalar state.
#
# The re-entrancy test in try/features/atomic_write_try.rb establishes a
# happens-before relationship via a Queue rendezvous: by the time thread
# B calls acquire, the ivar is already non-nil and B's check short-
# circuits even without the mutex. That test would still pass if the
# synchronize wrapper were removed.
#
# This file exercises the CAS race as directly as the MRI scheduler
# permits: N threads synchronised on a CyclicBarrier, released
# simultaneously, all calling atomic_write on a fresh instance where
# @atomic_write_owner is nil. With the mutex, exactly one thread wins
# and the others raise OperationModeError.
#
# Caveat: MRI's GVL serialises Ruby bytecode and only pre-empts at safe
# points, so many iterations INCREASE THE PROBABILITY of catching a
# pre-emption window between the nil-check and the set in
# acquire_atomic_write_ownership! but cannot guarantee it. A pure
# mutation test (removing the mutex) may still pass on some machines if
# GVL scheduling happens to serialise the threads after barrier release.
# This test's primary job is to assert the exact-one-winner invariant on
# simultaneous barrier release; the Fiber-based re-entrancy tests in
# try/features/atomic_write_try.rb additionally validate the guard's
# semantics when happens-before ordering is established.
#
# The test still earns its place: on loaded CI runners the GVL does
# pre-empt across iterations; on JRuby/TruffleRuby (which lack a GVL)
# the race is real every iteration; and even on unloaded MRI the
# "exact-one-winner" invariant is a smoke test that catches gross
# regressions (e.g. removing the @atomic_write_owner check entirely,
# which would let every thread pass the guard and open parallel MULTIs).

Familia.debug = false

class CASRacePlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :winner
  set :marks
end

CASRacePlan.instances.clear rescue nil
CASRacePlan.all.each(&:destroy!) rescue nil

## CAS race: exactly one thread per iteration wins atomic_write ownership
@iterations = 100
@threads_per_iteration = 10
@success_counter = Concurrent::AtomicFixnum.new(0)
@raise_counter = Concurrent::AtomicFixnum.new(0)
@unexpected_errors = Concurrent::Array.new
@winner_values = Concurrent::Array.new

@iterations.times do |iter|
  # Fresh instance per iteration: @atomic_write_owner must be nil when
  # threads start. Reusing across iterations lets the prior owner leak.
  plan = CASRacePlan.new(planid: "cas_race_#{iter}", winner: 'initial')
  plan.save

  barrier = Concurrent::CyclicBarrier.new(@threads_per_iteration)

  threads = @threads_per_iteration.times.map do |tid|
    Thread.new do
      barrier.wait  # Release all threads simultaneously
      begin
        plan.atomic_write do
          plan.winner = "thread_#{tid}"
          plan.marks.add("mark_#{tid}")
        end
        @success_counter.increment
      rescue Familia::OperationModeError => e
        if e.message.include?('another Fiber or Thread')
          @raise_counter.increment
        else
          @unexpected_errors << [:wrong_message, e.message]
        end
      rescue => e
        @unexpected_errors << [:wrong_class, e.class.name, e.message]
      end
    end
  end

  threads.each(&:join)

  reloaded = CASRacePlan.find_by_id("cas_race_#{iter}")
  @winner_values << reloaded.winner if reloaded
end

[
  @success_counter.value,
  @raise_counter.value,
  @unexpected_errors.to_a,
  @winner_values.size,
]
#=> [100, 900, [], 100]

## Every persisted winner reflects a single thread's update (no mix of writes)
# Each winner must match the "thread_N" pattern -- if two threads had
# both opened parallel MULTIs, persist_to_storage could interleave and
# produce values that neither thread set. A perfect pass guarantees
# exactly one winner serialised its update per iteration.
@winner_values.all? { |w| w =~ /\Athread_\d+\z/ }
#==> _ == true

## All marks sets contain exactly one member (the winning thread's mark)
# SADD is additive, so if two threads had opened parallel MULTIs and both
# got past the guard, their respective thread_N mark values would both
# land and the set would have >= 2 distinct members. A set size of 1
# per iteration is a second-order witness that exactly one thread
# executed the MULTI body.
@marks_counts = @iterations.times.map do |iter|
  reloaded = CASRacePlan.find_by_id("cas_race_#{iter}")
  reloaded ? reloaded.marks.members.size : -1
end
@marks_counts.all? { |c| c == 1 }
#==> _ == true

# Teardown
CASRacePlan.instances.clear rescue nil
CASRacePlan.all.each(&:destroy!) rescue nil
