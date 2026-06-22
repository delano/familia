# try/thread_safety/atomic_write_ownership_race_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

# Deterministic thread-safety tests for acquire_atomic_write_ownership!.
#
# These tests use Queue-based rendezvous to guarantee happens-before
# ordering, so the outcome is deterministic regardless of GVL scheduling.
# The probabilistic stress variant lives in
# try/support/stress/atomic_write_ownership_stress.rb for manual/periodic
# validation outside CI.

Familia.debug = false

class OwnershipGuardPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :name
  set :marks
end

OwnershipGuardPlan.instances.clear rescue nil
OwnershipGuardPlan.all.each(&:destroy!) rescue nil

## Thread ownership guard: second thread raises OperationModeError on same instance
@plan = OwnershipGuardPlan.new(planid: 'guard_thread', name: 'initial')
@plan.save
@enter_signal = Queue.new
@exit_signal = Queue.new

@thread_a = Thread.new do
  @plan.atomic_write do
    @plan.name = 'thread_a_wrote'
    @plan.marks.add('mark_a')
    @enter_signal << :a_inside
    @exit_signal.pop
  end
  :a_done
end

@thread_b = Thread.new do
  @enter_signal.pop
  begin
    @plan.atomic_write do
      @plan.name = 'thread_b_wrote'
      @plan.marks.add('mark_b')
    end
    :b_done
  rescue Familia::OperationModeError => e
    e.message.include?('another Fiber or Thread') ? :b_rejected : :b_wrong_message
  ensure
    @exit_signal << :release
  end
end

@result_b = @thread_b.value
@result_a = @thread_a.value
[@result_a, @result_b]
#=> [:a_done, :b_rejected]

## Only the owning thread's mutations are persisted
@reloaded = OwnershipGuardPlan.find_by_id('guard_thread')
[@reloaded.name, @reloaded.marks.members]
#=> ['thread_a_wrote', ['mark_a']]

## Ownership is released after atomic_write completes: subsequent call succeeds
@plan2 = OwnershipGuardPlan.new(planid: 'guard_release', name: 'before')
@plan2.save
@plan2.atomic_write { @plan2.name = 'first_write' }
@plan2.atomic_write { @plan2.name = 'second_write' }
OwnershipGuardPlan.find_by_id('guard_release').name
#=> 'second_write'

## Ownership is released even when the block raises
@plan3 = OwnershipGuardPlan.new(planid: 'guard_exception', name: 'before')
@plan3.save
begin
  @plan3.atomic_write { raise 'boom' }
rescue RuntimeError
end
@plan3.atomic_write { @plan3.name = 'after_exception' }
OwnershipGuardPlan.find_by_id('guard_exception').name
#=> 'after_exception'

## Repeated thread contention: guard holds across N iterations
@iterations = 20
@results = @iterations.times.map do |i|
  plan = OwnershipGuardPlan.new(planid: "guard_repeat_#{i}", name: 'initial')
  plan.save
  enter = Queue.new
  release = Queue.new

  owner = Thread.new do
    plan.atomic_write do
      plan.name = "owner_#{i}"
      plan.marks.add("owner_mark_#{i}")
      enter << :ready
      release.pop
    end
    :owner_done
  end

  contender = Thread.new do
    enter.pop
    begin
      plan.atomic_write { plan.name = "contender_#{i}" }
      :contender_done
    rescue Familia::OperationModeError
      :contender_rejected
    ensure
      release << :go
    end
  end

  [owner.value, contender.value]
end

@results.all? { |owner, contender| owner == :owner_done && contender == :contender_rejected }
#=> true

## All iterated instances reflect only the owner's mutations
@persisted_correct = @iterations.times.all? do |i|
  r = OwnershipGuardPlan.find_by_id("guard_repeat_#{i}")
  r && r.name == "owner_#{i}" && r.marks.members == ["owner_mark_#{i}"]
end
@persisted_correct
#=> true

# Teardown
OwnershipGuardPlan.instances.clear rescue nil
OwnershipGuardPlan.all.each(&:destroy!) rescue nil
