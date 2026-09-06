# try/unit/horreum/related_field_lifecycle_try.rb
#
# frozen_string_literal: true

# Related-field configuration lifecycle (issue #428).
#
# Horreum.configure_related_field(name, **opts) merges options into a declared
# definition between the class body and first use. Definitions freeze at first
# materialization: instance-level ones together at the end of the first
# initialize_relatives (Klass.new or the load path), class-level ones one at a
# time on the first accessor call. Class-level collections are now built
# lazily, into a per-class cache (not @<name> on the class). Subclasses get
# deep-copied definitions. The shared definition Hash must never receive an
# instance-level :parent (that was a race). Declaration, re-declaration,
# configuration and the freeze all serialize on related_fields_mutex, which
# exists from class creation; DataType construction runs outside it. Class-
# level builds are single-flight under a per-class reentrant build lock, and
# the first instance builds from a registry snapshot, not the live Hash.
#
# Every class here is fresh and uniquely named (Rfl428*) because the shared
# test helper already materializes Customer/Session/CustomDomain at load, and
# all tryouts share constants and db 0.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# 1. configure-before-materialize on an instance-level field
class Rfl428Events < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end

# 2 + 5. class-level lazy build, per-definition freeze
class Rfl428Registry < Familia::Horreum
  identifier_field :id
  field :id
  class_sorted_set :registry, max_length: 3
  class_list :audit, max_length: 5
end

# 3. validation parity with the DataType constructor
class Rfl428Validate < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
  set :tags
end

# 4 + 6. freeze after instance materialization; class-level stays open
class Rfl428Frozen < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
  class_sorted_set :board, max_length: 4
end

# 6 (reverse). class-level materialization leaves instance-level open
class Rfl428ClassFirst < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
  class_sorted_set :board, max_length: 4
end

# 7. subclass independence, both directions
class Rfl428Parent < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end

class Rfl428Child < Rfl428Parent
end

class Rfl428ParentB < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end

class Rfl428ChildB < Rfl428ParentB
end

# 7h. inherited, non-redeclared class-level field is keyed under the subclass
class Rfl428SubKey < Rfl428Registry
end

# 8. load path materializes and freezes
class Rfl428Loaded < Familia::Horreum
  identifier_field :id
  field :id
  field :label
  sorted_set :events, max_length: 10
end

# 9. concurrent instance materialization
class Rfl428Concurrent < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events
end

# 10. concurrent class-level lazy build
class Rfl428LazyReg < Familia::Horreum
  identifier_field :id
  field :id
  class_sorted_set :registry, max_length: 9
end

# 11. registry entry replaced, not mutated
class Rfl428Replace < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end

# 13. re-declaration: unfrozen replaces, frozen raises, new names still attach
class Rfl428Redeclare < Familia::Horreum
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
  class_sorted_set :board, max_length: 4
end

# 15. scope: the same name at both levels
class Rfl428Scoped < Familia::Horreum
  identifier_field :id
  field :id
  zset :both, max_length: 10
  class_sorted_set :both, max_length: 100
  class_list :class_only, max_length: 3
  list :inst_only, max_length: 3
end

# 16. caller-owned opts Hash is never frozen or mutated by the lifecycle
class Rfl428Owned < Familia::Horreum
  identifier_field :id
  field :id
end

# 19. a pre-existing class instance variable sharing a class-level field's
# name must not be served as the collection
class Rfl428Preexisting < Familia::Horreum
  identifier_field :id
  field :id
  @registry = :preexisting
  class_list :registry, max_length: 4
end

# 20. a custom DataType whose init reads another class-level collection of
# the same Horreum class. Construction must run outside related_fields_mutex
# or this deadlocks (ThreadError: deadlock; recursive locking).
class Rfl428ChainedList < Familia::ListKey
  attr_reader :sibling_dbkey

  def init
    @sibling_dbkey = parent.model_klass.registry.dbkey
  end
end

class Rfl428Chain < Familia::Horreum
  identifier_field :id
  field :id
  class_sorted_set :registry, max_length: 3
  attach_class_related_field :chain, Rfl428ChainedList, {}
end

class Rfl428ChainInst < Familia::Horreum
  identifier_field :id
  field :id
  class_sorted_set :registry, max_length: 3
  attach_instance_related_field :trail, Rfl428ChainedList, {}
end

# 21d. cross-thread: one thread builds :chain (re-entering the build lock for
# :registry from init) while another asks for :registry directly
class Rfl428ChainRace < Familia::Horreum
  identifier_field :id
  field :id
  class_sorted_set :registry, max_length: 3
  attach_class_related_field :chain, Rfl428ChainedList, {}
end

# 10b. a custom DataType whose init has a side effect (a counter) and a widened
# window. The class-level build must run it exactly once per field.
class Rfl428CountedList < Familia::ListKey
  @constructions = Concurrent::AtomicFixnum.new(0)
  class << self
    attr_reader :constructions
  end

  def init
    self.class.constructions.increment
    Thread.pass
    sleep 0.001
  end
end

class Rfl428SingleFlight < Familia::Horreum
  identifier_field :id
  field :id
  attach_class_related_field :counted, Rfl428CountedList, {}
end

# 12. Widens the read-build-freeze window in initialize_relatives so the GVL
# interleaves the materializing thread with configure_related_field. Inert
# until +active+ is set; the race block turns it on and off again.
module Rfl428SlowBuild
  class << self
    attr_accessor :active
  end

  def initialize(*args, **kwargs)
    if Rfl428SlowBuild.active
      Thread.pass
      sleep 0.0005
    end
    super
  end
end
Rfl428SlowBuild.active = false

def rfl428_capture
  yield
  nil
rescue StandardError => e
  e
end

@rfl428_run = Familia.now.to_i.to_s
@rfl428_instances = []
@rfl428_classes = [
  Rfl428Events, Rfl428Registry, Rfl428Validate, Rfl428Frozen, Rfl428ClassFirst,
  Rfl428Parent, Rfl428Child, Rfl428ParentB, Rfl428ChildB, Rfl428SubKey, Rfl428Loaded,
  Rfl428Concurrent, Rfl428LazyReg, Rfl428Replace, Rfl428Redeclare, Rfl428Scoped, Rfl428Owned,
  Rfl428Preexisting, Rfl428Chain, Rfl428ChainInst, Rfl428ChainRace, Rfl428SingleFlight,
]

## 1a. Configuring max_length before the first instance is reflected on that instance
Rfl428Events.configure_related_field(:events, max_length: 20)
@ev = Rfl428Events.new(id: "ev-#{@rfl428_run}")
@rfl428_instances << @ev
@ev.events.max_length
#=> 20

## 1b. A second configure merges: default_expiration added, max_length kept (fresh class)
klass = Class.new(Familia::Horreum) do
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end
klass.configure_related_field(:events, max_length: 20)
klass.configure_related_field(:events, default_expiration: 3600)
definition = klass.related_fields[:events]
[definition.opts[:max_length], definition.opts[:default_expiration]]
#=> [20, 3600]

## 1c. The merged default_expiration and max_length both reach the built DataType
klass = Class.new(Familia::Horreum) do
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end
klass.configure_related_field(:events, default_expiration: 3600)
inst = klass.new(id: 'anon-1c')
[inst.events.max_length, inst.events.default_expiration]
#=> [10, 3600]

## 2a. Class-level: configure before first access is honored by the lazy build
Rfl428Registry.configure_related_field(:registry, max_length: 7)
Rfl428Registry.registry.max_length
#=> 7

## 2b. Repeated class-level access returns the same object
Rfl428Registry.registry.equal?(Rfl428Registry.registry)
#=> true

## 2c. The materialized class-level DataType is frozen
Rfl428Registry.registry.frozen?
#=> true

## 2d. registry? is false while empty, true after an add
before = Rfl428Registry.registry?
Rfl428Registry.registry.add("m-#{@rfl428_run}", 1)
[before, Rfl428Registry.registry?]
#=> [false, true]

## 2e. Klass.registry= still dispatches to send(name).replace (no DataType defines replace, unchanged)
err = rfl428_capture { Rfl428Registry.registry = ['x'] }
[err.class, err.name]
#=> [NoMethodError, :replace]

## 2f. The class-level dbkey is unchanged by lazy construction (prefix:name)
Rfl428Registry.registry.dbkey
#=> "#{Rfl428Registry.prefix}:registry"

## 3a. Unknown field name raises ArgumentError naming the class and field
Rfl428Validate.configure_related_field(:nope, max_length: 5)
#=!> ArgumentError
#=~> /Rfl428Validate has no related field :nope/

## 3b. Negative max_length: same class and message as direct construction
direct = rfl428_capture { Familia::SortedSet.new('x', max_length: -1) }
cfg = rfl428_capture { Rfl428Validate.configure_related_field(:events, max_length: -1) }
[cfg.class, cfg.message == direct.message, direct.message]
#=> [ArgumentError, true, 'max_length must be a positive Integer, got -1']

## 3c. Zero max_length: same class and message as direct construction
direct = rfl428_capture { Familia::SortedSet.new('x', max_length: 0) }
cfg = rfl428_capture { Rfl428Validate.configure_related_field(:events, max_length: 0) }
[cfg.class, cfg.message == direct.message]
#=> [ArgumentError, true]

## 3d. String max_length: same class and message as direct construction
direct = rfl428_capture { Familia::SortedSet.new('x', max_length: '10') }
cfg = rfl428_capture { Rfl428Validate.configure_related_field(:events, max_length: '10') }
[cfg.class, cfg.message == direct.message, direct.message]
#=> [ArgumentError, true, 'max_length must be a positive Integer, got "10"']

## 3e. max_length on an unsupported type (set) matches direct construction
set_klass = Rfl428Validate.related_fields[:tags].klass
direct = rfl428_capture { set_klass.new('x', max_length: 5) }
cfg = rfl428_capture { Rfl428Validate.configure_related_field(:tags, max_length: 5) }
[set_klass, cfg.class, cfg.message == direct.message, direct.message]
#=> [Familia::UnsortedSet, ArgumentError, true, 'max_length is not supported by Familia::UnsortedSet (only SortedSet and ListKey trim on write)']

## 3f. Invalid dirty_write_warnings mode matches direct construction
direct = rfl428_capture { Familia::SortedSet.new('x', dirty_write_warnings: :loud) }
cfg = rfl428_capture { Rfl428Validate.configure_related_field(:events, dirty_write_warnings: :loud) }
[cfg.class, cfg.message == direct.message, direct.message]
#=> [ArgumentError, true, 'dirty_write_warnings must be one of [:strict, :warn, :once, :off], got :loud']

## 3g. A failed configure leaves the definition untouched (same object, same opts)
before = Rfl428Validate.related_fields[:events]
rfl428_capture { Rfl428Validate.configure_related_field(:events, max_length: -1) }
rfl428_capture { Rfl428Validate.configure_related_field(:events, dirty_write_warnings: :loud) }
after = Rfl428Validate.related_fields[:events]
[after.equal?(before), after.opts[:max_length], after.opts.key?(:dirty_write_warnings), after.opts.frozen?]
#=> [true, 10, false, false]

## 3h. Validation is on the merged hash: a valid second key cannot sneak past an invalid first
rfl428_capture { Rfl428Validate.configure_related_field(:events, max_length: -1, dirty_write_warnings: :off) }.class
#=> ArgumentError

## 4a. Klass.new alone materializes and freezes instance-level definitions
before = Rfl428Frozen.related_fields[:events].opts.frozen?
@fz = Rfl428Frozen.new(id: "fz-#{@rfl428_run}")
@rfl428_instances << @fz
[before, Rfl428Frozen.related_fields[:events].opts.frozen?]
#=> [false, true]

## 4b. Configuring a frozen instance-level field raises RelatedFieldFrozenError
Rfl428Frozen.configure_related_field(:events, max_length: 99)
#=!> Familia::RelatedFieldFrozenError
#=~> /Rfl428Frozen#events/
#=~> /instances already exist/

## 4c. RelatedFieldFrozenError is a HorreumError and a Familia::Problem
[Familia::RelatedFieldFrozenError < Familia::HorreumError, Familia::RelatedFieldFrozenError < Familia::Problem]
#=> [true, true]

## 4d. The frozen definition's opts are frozen; direct mutation raises FrozenError
Rfl428Frozen.related_fields[:events].opts[:max_length] = 1
#=!> FrozenError

## 4e. The instance's DataType still reflects the declared cap, not the refused one
@fz.events.max_length
#=> 10

## 5a. Class-level: first access freezes only that definition
Rfl428Registry.related_fields
Rfl428Registry.registry # already built in 2a
[Rfl428Registry.class_related_fields[:registry].opts.frozen?,
 Rfl428Registry.class_related_fields[:audit].opts.frozen?]
#=> [true, false]

## 5b. Configuring the built class-level field raises RelatedFieldFrozenError
Rfl428Registry.configure_related_field(:registry, max_length: 8)
#=!> Familia::RelatedFieldFrozenError
#=~> /Rfl428Registry\.registry/
#=~> /already built/

## 5c. A different, untouched class-level field on the same class still configures
Rfl428Registry.configure_related_field(:audit, max_length: 6)
Rfl428Registry.class_related_fields[:audit].opts[:max_length]
#=> 6

## 5d. Touching Klass.instances (auto class_sorted_set) freezes only :instances
Rfl428Registry.instances
[Rfl428Registry.class_related_fields[:instances].opts.frozen?,
 Rfl428Registry.class_related_fields[:audit].opts.frozen?]
#=> [true, false]

## 5e. Saving an instance (which touches Klass.instances) also leaves :audit configurable
@reg_inst = Rfl428Registry.new(id: "reg-#{@rfl428_run}")
@rfl428_instances << @reg_inst
@reg_inst.save
Rfl428Registry.configure_related_field(:audit, max_length: 12)
[Rfl428Registry.class_related_fields[:audit].opts[:max_length],
 Rfl428Registry.class_related_fields[:audit].opts.frozen?]
#=> [12, false]

## 5f. The late class-level configure is honored by the lazy build
Rfl428Registry.audit.max_length
#=> 12

## 6a. Instance materialization does not freeze class-level definitions
# Rfl428Frozen.new ran in 4a; :board has never been accessed.
Rfl428Frozen.class_related_fields[:board].opts.frozen?
#=> false

## 6b. ...and that class-level field is still configurable, then honored
Rfl428Frozen.configure_related_field(:board, max_length: 40)
Rfl428Frozen.board.max_length
#=> 40

## 6c. Class-level materialization does not freeze instance-level definitions
Rfl428ClassFirst.board
[Rfl428ClassFirst.class_related_fields[:board].opts.frozen?,
 Rfl428ClassFirst.related_fields[:events].opts.frozen?]
#=> [true, false]

## 6d. ...and the instance-level field is still configurable, then honored
Rfl428ClassFirst.configure_related_field(:events, max_length: 21)
inst = Rfl428ClassFirst.new(id: "cf-#{@rfl428_run}")
@rfl428_instances << inst
inst.events.max_length
#=> 21

## 7a. Subclass and parent hold distinct opts Hashes for the same field
parent_opts = Rfl428Parent.related_fields[:events].opts
child_opts = Rfl428Child.related_fields[:events].opts
[parent_opts.equal?(child_opts), parent_opts == child_opts]
#=> [false, true]

## 7b. Instantiating the subclass freezes only the subclass's definition
inst = Rfl428Child.new(id: "ch-#{@rfl428_run}")
@rfl428_instances << inst
[Rfl428Child.related_fields[:events].opts.frozen?,
 Rfl428Parent.related_fields[:events].opts.frozen?]
#=> [true, false]

## 7c. The parent can still be configured after the subclass materialized
Rfl428Parent.configure_related_field(:events, max_length: 11)
Rfl428Parent.related_fields[:events].opts[:max_length]
#=> 11

## 7d. Configuring the parent after subclassing does not leak into the subclass
Rfl428Child.related_fields[:events].opts[:max_length]
#=> 10

## 7e. Vice versa: instantiating the parent freezes only the parent's definition
inst = Rfl428ParentB.new(id: "pb-#{@rfl428_run}")
@rfl428_instances << inst
[Rfl428ParentB.related_fields[:events].opts.frozen?,
 Rfl428ChildB.related_fields[:events].opts.frozen?]
#=> [true, false]

## 7f. ...and the subclass can still be configured and honors it
Rfl428ChildB.configure_related_field(:events, max_length: 12)
inst = Rfl428ChildB.new(id: "cb-#{@rfl428_run}")
@rfl428_instances << inst
inst.events.max_length
#=> 12

## 7g. A subclass created AFTER the parent configured inherits the configured value
klass = Class.new(Rfl428Parent)
klass.related_fields[:events].opts[:max_length]
#=> 11

## 7h. An inherited, non-redeclared class-level field is keyed under the subclass, not the declaring class
[Rfl428SubKey.registry.dbkey != Rfl428Registry.registry.dbkey,
 Rfl428SubKey.registry.parent.model_klass == Rfl428SubKey,
 Rfl428SubKey.registry.dbkey]
#=> [true, true, "#{Rfl428SubKey.prefix}:registry"]

## 7i. An explicit user-supplied parent: survives inheritance untouched
klass = Class.new(Familia::Horreum) do
  identifier_field :id
  field :id
  class_list :shared, parent: Rfl428Registry
end
sub = Class.new(klass)
sub.class_related_fields[:shared].opts[:parent].equal?(Rfl428Registry)
#=> true

## 8a. Load path: the first materialization via Klass.load honors the configured value
# Write the object hash directly so no instance exists before load.
Rfl428Loaded.configure_related_field(:events, max_length: 33)
@ld_id = "ld-#{@rfl428_run}"
Rfl428Loaded.dbclient.hset(Rfl428Loaded.dbkey(@ld_id), 'id', @ld_id, 'label', '"loaded"')
before = Rfl428Loaded.related_fields[:events].opts.frozen?
@loaded = Rfl428Loaded.load(@ld_id)
@rfl428_instances << @loaded
[before, @loaded.class, @loaded.label, @loaded.events.max_length]
#=> [false, Rfl428Loaded, 'loaded', 33]

## 8b. Load path freezes the definition; a later configure raises
after = Rfl428Loaded.related_fields[:events].opts.frozen?
err = rfl428_capture { Rfl428Loaded.configure_related_field(:events, max_length: 34) }
[after, err.class]
#=> [true, Familia::RelatedFieldFrozenError]

## 8c. The loaded instance's DataType keys off its own identifier
@loaded.events.dbkey
#=> "#{Rfl428Loaded.prefix}:#{@ld_id}:events"

## 9a. Concurrent instance materialization: every DataType references its own instance
results = Array.new(8)
threads = 8.times.map do |i|
  Thread.new do
    inst = Rfl428Concurrent.new(id: "cc-#{@rfl428_run}-#{i}")
    ref = inst.events.instance_variable_get(:@parent_ref)
    results[i] = [ref.equal?(inst), inst.events.parent.identifier == inst.identifier, inst.events.dbkey]
  end
end
threads.each(&:join)
[results.all? { |ok_ref, ok_id, _| ok_ref && ok_id }, results.map(&:last).uniq.size]
#=> [true, 8]

## 9b. The shared definition never received an instance :parent
opts = Rfl428Concurrent.related_fields[:events].opts
[opts.key?(:parent), opts.frozen?]
#=> [false, true]

## 10. Concurrent class-level lazy build: all threads get the same object
seen = Array.new(8)
latch = Queue.new
threads = 8.times.map do |i|
  Thread.new do
    latch.pop
    seen[i] = Rfl428LazyReg.registry
  end
end
8.times { latch << true }
threads.each(&:join)
[seen.all? { |dt| dt.equal?(seen.first) }, seen.first.max_length, seen.first.frozen?]
#=> [true, 9, true]

## 10b. Concurrent class-level lazy build constructs the DataType exactly once
# Rfl428CountedList#init counts constructions and widens the window. Before
# the per-class build lock, every thread that missed the cache constructed
# its own copy (8 threads, 8 init calls) and only the first store survived.
seen = Array.new(8)
latch = Queue.new
threads = 8.times.map do |i|
  Thread.new do
    latch.pop
    seen[i] = Rfl428SingleFlight.counted
  end
end
8.times { latch << true }
threads.each(&:join)
[seen.all? { |dt| dt.equal?(seen.first) }, seen.first.class, Rfl428CountedList.constructions.value]
#=> [true, Rfl428CountedList, 1]

## 10c. A later access still returns the cached object without constructing again
[Rfl428SingleFlight.counted.equal?(seen.first), Rfl428CountedList.constructions.value]
#=> [true, 1]

## 11a. configure_related_field returns a RelatedFieldDefinition
@old_def = Rfl428Replace.related_fields[:events]
@new_def = Rfl428Replace.configure_related_field(:events, max_length: 15)
@new_def
#=:> Familia::RelatedFieldDefinition

## 11b. The registry now holds the returned definition; the old one is untouched
[Rfl428Replace.related_fields[:events].equal?(@new_def),
 @new_def.equal?(@old_def),
 @old_def.opts[:max_length], @new_def.opts[:max_length],
 @new_def.name, @new_def.klass]
#=> [true, false, 10, 15, :events, Familia::SortedSet]

## 11c. The old definition's opts Hash was not mutated or frozen by the replace
[@old_def.opts.frozen?, @old_def.opts.equal?(@new_def.opts)]
#=> [false, false]

## 12a. Race: first materialization vs configure_related_field never splits a class
# Thread A builds the first instance (read definitions, build, freeze) while
# thread B reconfigures the same field. Either B wins and every instance
# sees 20, or B is refused (frozen) and every instance sees 10. The window
# is widened by Rfl428SlowBuild (prepended onto SortedSet#initialize); without
# the mutex in initialize_relatives this yields :mixed outcomes.
Familia::SortedSet.prepend(Rfl428SlowBuild) unless Familia::SortedSet.ancestors.include?(Rfl428SlowBuild)
Rfl428SlowBuild.active = true
@race_tally = Hash.new(0)
@race_mixed = []
begin
  60.times do |i|
    klass = Class.new(Familia::Horreum) do
      identifier_field :id
      field :id
      sorted_set :events, max_length: 10
    end
    barrier = Queue.new
    inst_a = nil
    cfg_err = nil
    jitter = rand(0..300)
    ta = Thread.new { barrier.pop; inst_a = klass.new(id: "race-a-#{i}") }
    tb = Thread.new do
      barrier.pop
      jitter.times { Thread.pass }
      begin
        klass.configure_related_field(:events, max_length: 20)
      rescue Familia::RelatedFieldFrozenError => e
        cfg_err = e
      end
    end
    2.times { barrier << true }
    [ta, tb].each(&:join)
    inst_b = klass.new(id: "race-b-#{i}")
    a = inst_a.events.max_length
    b = inst_b.events.max_length
    outcome =
      if cfg_err
        (a == 10 && b == 10) ? :frozen : :mixed
      else
        (a == 20 && b == 20) ? :configured : :mixed
      end
    @race_tally[outcome] += 1
    @race_mixed << [i, a, b, cfg_err&.class] if outcome == :mixed
    Familia.members.delete(klass)
  end
ensure
  Rfl428SlowBuild.active = false
end
@race_mixed
#=> []

## 12b. Every iteration was classified, and the slow-build hook is off again
[@race_tally.values.sum, @race_tally.keys - %i[configured frozen], Rfl428SlowBuild.active]
#=> [60, [], false]

## 13a. Re-declaring an UNFROZEN instance-level field replaces the definition
Rfl428Redeclare.sorted_set :events, max_length: 15
definition = Rfl428Redeclare.related_fields[:events]
[definition.opts[:max_length], definition.opts.frozen?]
#=> [15, false]

## 13b. Re-declaring an UNFROZEN class-level field replaces the definition
Rfl428Redeclare.class_sorted_set :board, max_length: 5
definition = Rfl428Redeclare.class_related_fields[:board]
[definition.opts[:max_length], definition.opts.frozen?]
#=> [5, false]

## 13c. Instance-level re-declare after Klass.new raises RelatedFieldFrozenError
@rd = Rfl428Redeclare.new(id: "rd-#{@rfl428_run}")
@rfl428_instances << @rd
Rfl428Redeclare.sorted_set :events, max_length: 20
#=!> Familia::RelatedFieldFrozenError
#=~> /Rfl428Redeclare#events is already materialized; re-declaration is not allowed/

## 13d. The refused re-declare left the frozen definition and the instance untouched
definition = Rfl428Redeclare.related_fields[:events]
[definition.opts[:max_length], definition.opts.frozen?, @rd.events.max_length]
#=> [15, true, 15]

## 13e. Class-level re-declare after the first accessor call raises
Rfl428Redeclare.board
Rfl428Redeclare.class_sorted_set :board, max_length: 6
#=!> Familia::RelatedFieldFrozenError
#=~> /Rfl428Redeclare\.board is already materialized; re-declaration is not allowed/

## 13f. ...and the built collection still serves the pre-freeze options
[Rfl428Redeclare.board.max_length, Rfl428Redeclare.class_related_fields[:board].opts[:max_length]]
#=> [5, 5]

## 13g. Declaring a brand-new field on a materialized class still works; new instances get it
Rfl428Redeclare.list :log, max_length: 3
inst = Rfl428Redeclare.new(id: "rd2-#{@rfl428_run}")
@rfl428_instances << inst
[inst.log.class, inst.log.max_length, Rfl428Redeclare.related_fields[:log].opts.frozen?]
#=> [Familia::ListKey, 3, true]

## 13h. A named subclass of a materialized parent still gets its own :instances (no raise in inherited)
Rfl428Redeclare.instances # materialize the parent's class_sorted_set :instances
err = rfl428_capture { Object.const_set(:Rfl428RedeclareChild, Class.new(Rfl428Redeclare)) }
@rfl428_classes << Rfl428RedeclareChild
[err,
 Rfl428RedeclareChild.class_related_fields[:instances].opts.frozen?,
 Rfl428RedeclareChild.related_fields[:events].opts.frozen?,
 Rfl428RedeclareChild.instances.dbkey == Rfl428Redeclare.instances.dbkey,
 Rfl428RedeclareChild.instances.dbkey]
#=> [nil, false, false, false, "#{Rfl428RedeclareChild.prefix}:instances"]

## 14a. class_set with max_length raises in the class body with the constructor's error
direct = rfl428_capture { Familia::UnsortedSet.new('x', max_length: 5) }
decl = rfl428_capture do
  Class.new(Familia::Horreum) do
    identifier_field :id
    field :id
    class_set :tags, max_length: 5
  end
end
[decl.class, decl.message == direct.message, direct.message]
#=> [ArgumentError, true, 'max_length is not supported by Familia::UnsortedSet (only SortedSet and ListKey trim on write)']

## 14b. Instance-level set with max_length raises in the class body with the constructor's error
direct = rfl428_capture { Familia::UnsortedSet.new('x', max_length: 5) }
decl = rfl428_capture do
  Class.new(Familia::Horreum) do
    identifier_field :id
    field :id
    set :tags, max_length: 5
  end
end
[decl.class, decl.message == direct.message]
#=> [ArgumentError, true]

## 14c. class_sorted_set with max_length: 0 raises in the class body with the constructor's error
direct = rfl428_capture { Familia::SortedSet.new('x', max_length: 0) }
decl = rfl428_capture do
  Class.new(Familia::Horreum) do
    identifier_field :id
    field :id
    class_sorted_set :t, max_length: 0
  end
end
[decl.class, decl.message == direct.message, direct.message]
#=> [ArgumentError, true, 'max_length must be a positive Integer, got 0']

## 14d. A refused declaration leaves no definition behind
klass = Class.new(Familia::Horreum) do
  identifier_field :id
  field :id
end
rfl428_capture { klass.sorted_set :bad, max_length: -1 }
rfl428_capture { klass.class_sorted_set :bad, max_length: -1 }
[klass.related_fields.key?(:bad), klass.class_related_fields.key?(:bad),
 klass.method_defined?(:bad), klass.respond_to?(:bad)]
#=> [false, false, false, false]

## 15a. Default scope changes the instance-level definition only
Rfl428Scoped.configure_related_field(:both, max_length: 11)
[Rfl428Scoped.related_fields[:both].opts[:max_length],
 Rfl428Scoped.class_related_fields[:both].opts[:max_length]]
#=> [11, 100]

## 15b. scope: :class changes the class-level definition only
Rfl428Scoped.configure_related_field(:both, scope: :class, max_length: 101)
[Rfl428Scoped.related_fields[:both].opts[:max_length],
 Rfl428Scoped.class_related_fields[:both].opts[:max_length]]
#=> [11, 101]

## 15c. scope: :instance addresses the instance-level definition explicitly
Rfl428Scoped.configure_related_field(:both, scope: :instance, max_length: 12)
[Rfl428Scoped.related_fields[:both].opts[:max_length],
 Rfl428Scoped.class_related_fields[:both].opts[:max_length]]
#=> [12, 101]

## 15d. scope: :instance on a class-only name raises ArgumentError
Rfl428Scoped.configure_related_field(:class_only, scope: :instance, max_length: 4)
#=!> ArgumentError
#=~> /Rfl428Scoped has no instance-level related field :class_only/

## 15e. scope: :class on an instance-only name raises ArgumentError
Rfl428Scoped.configure_related_field(:inst_only, scope: :class, max_length: 4)
#=!> ArgumentError
#=~> /Rfl428Scoped has no class-level related field :inst_only/

## 15f. An unknown scope raises ArgumentError before any lookup
Rfl428Scoped.configure_related_field(:both, scope: :both, max_length: 4)
#=!> ArgumentError
#=~> /scope must be nil, :instance or :class, got :both/

## 15g. A class-only name with the default scope still resolves (backward compat)
Rfl428Scoped.configure_related_field(:class_only, max_length: 4)
Rfl428Scoped.class_related_fields[:class_only].opts[:max_length]
#=> 4

## 15h. Freezing one level leaves the other configurable, and the error names the level
Rfl428Scoped.both # class-level accessor: freezes only class_related_fields[:both]
err = rfl428_capture { Rfl428Scoped.configure_related_field(:both, scope: :class, max_length: 102) }
Rfl428Scoped.configure_related_field(:both, max_length: 13)
[err.class, err.message.match?(/class-level \S*Rfl428Scoped\.both: the collection was already built/),
 Rfl428Scoped.related_fields[:both].opts[:max_length],
 Rfl428Scoped.both.max_length]
#=> [Familia::RelatedFieldFrozenError, true, 13, 101]

## 15i. Both definitions reach their own DataType with their own options
inst = Rfl428Scoped.new(id: "sc-#{@rfl428_run}")
@rfl428_instances << inst
[inst.both.max_length, Rfl428Scoped.both.max_length, inst.both.dbkey == Rfl428Scoped.both.dbkey]
#=> [13, 101, false]

## 16a. A caller-owned opts Hash is copied, not frozen, by instance-level materialization
@owned = { max_length: 10 }
Rfl428Owned.sorted_set :events, @owned
inst = Rfl428Owned.new(id: "own-#{@rfl428_run}")
@rfl428_instances << inst
definition = Rfl428Owned.related_fields[:events]
[@owned.frozen?, definition.opts.frozen?, definition.opts.equal?(@owned), inst.events.max_length]
#=> [false, true, false, 10]

## 16b. Mutating the caller's Hash afterwards neither raises nor reaches the definition
@owned[:max_length] = 99
[@owned[:max_length], Rfl428Owned.related_fields[:events].opts[:max_length]]
#=> [99, 10]

## 16c. Same for a class-level declaration built lazily on first access
@owned_class = { max_length: 7 }
Rfl428Owned.class_list :audit, @owned_class
Rfl428Owned.audit
definition = Rfl428Owned.class_related_fields[:audit]
@owned_class[:max_length] = 99
[@owned_class.frozen?, definition.opts.frozen?, definition.opts[:max_length], Rfl428Owned.audit.max_length]
#=> [false, true, 7, 7]

## 17a. Race: first materialization vs instance-level re-declaration never splits a class
# Same shape as 12a, but thread B re-declares (`sorted_set :events` again)
# instead of calling configure_related_field. Re-declaration's frozen? check
# and registry replacement run under related_fields_mutex, so either B lands
# before the freeze (every instance sees 20, registry frozen at 20) or B is
# refused (every instance sees 10). Unlocked, B could pass the check while
# A was building, leaving the first instance on 10 and the registry on 20.
Familia::SortedSet.prepend(Rfl428SlowBuild) unless Familia::SortedSet.ancestors.include?(Rfl428SlowBuild)
Rfl428SlowBuild.active = true
@redecl_tally = Hash.new(0)
@redecl_mixed = []
begin
  60.times do |i|
    klass = Class.new(Familia::Horreum) do
      identifier_field :id
      field :id
      sorted_set :events, max_length: 10
    end
    barrier = Queue.new
    inst_a = nil
    decl_err = nil
    jitter = rand(0..300)
    ta = Thread.new { barrier.pop; inst_a = klass.new(id: "redecl-a-#{i}") }
    tb = Thread.new do
      barrier.pop
      jitter.times { Thread.pass }
      begin
        klass.sorted_set :events, max_length: 20
      rescue Familia::RelatedFieldFrozenError => e
        decl_err = e
      end
    end
    2.times { barrier << true }
    [ta, tb].each(&:join)
    inst_b = klass.new(id: "redecl-b-#{i}")
    definition = klass.related_fields[:events]
    a = inst_a.events.max_length
    b = inst_b.events.max_length
    r = definition.opts[:max_length]
    outcome =
      if decl_err
        (a == 10 && b == 10 && r == 10) ? :frozen : :mixed
      else
        (a == 20 && b == 20 && r == 20) ? :redeclared : :mixed
      end
    @redecl_tally[outcome] += 1
    @redecl_mixed << [i, a, b, r, definition.opts.frozen?, decl_err&.class] if outcome == :mixed
    Familia.members.delete(klass)
  end
ensure
  Rfl428SlowBuild.active = false
end
@redecl_mixed
#=> []

## 17b. Every iteration was classified as one of the two legal outcomes
[@redecl_tally.values.sum, @redecl_tally.keys - %i[redeclared frozen]]
#=> [60, []]

## 18a. Race: first class-level access vs class-level re-declaration never splits cache and registry
# Thread A calls Klass.registry (lazy build) while thread B re-declares
# `class_sorted_set :registry, max_length: 30`. Either B lands before A's
# freeze (built collection AND registry say 30) or B is refused (both say
# 10). Unlocked, A could cache a collection built on 10 while the registry
# moved to 30 and stayed configurable.
Rfl428SlowBuild.active = true
@cls_redecl_tally = Hash.new(0)
@cls_redecl_mixed = []
begin
  60.times do |i|
    klass = Class.new(Familia::Horreum) do
      identifier_field :id
      field :id
      class_sorted_set :registry, max_length: 10
    end
    barrier = Queue.new
    built_a = nil
    decl_err = nil
    jitter = rand(0..300)
    ta = Thread.new { barrier.pop; built_a = klass.registry }
    tb = Thread.new do
      barrier.pop
      jitter.times { Thread.pass }
      begin
        klass.class_sorted_set :registry, max_length: 30
      rescue Familia::RelatedFieldFrozenError => e
        decl_err = e
      end
    end
    2.times { barrier << true }
    [ta, tb].each(&:join)
    definition = klass.class_related_fields[:registry]
    a = built_a.max_length
    c = klass.registry.max_length
    r = definition.opts[:max_length]
    outcome =
      if decl_err
        (a == 10 && c == 10 && r == 10 && definition.opts.frozen?) ? :frozen : :mixed
      else
        (a == 30 && c == 30 && r == 30 && definition.opts.frozen?) ? :redeclared : :mixed
      end
    @cls_redecl_tally[outcome] += 1
    @cls_redecl_mixed << [i, a, c, r, definition.opts.frozen?, decl_err&.class] if outcome == :mixed
    Familia.members.delete(klass)
  end
ensure
  Rfl428SlowBuild.active = false
end
@cls_redecl_mixed
#=> []

## 18b. Every iteration was classified, and the slow-build hook is off again
[@cls_redecl_tally.values.sum, @cls_redecl_tally.keys - %i[redeclared frozen], Rfl428SlowBuild.active]
#=> [60, [], false]

## 19a. related_fields_mutex exists before first use and is the object the accessor returns
# `@mutex ||= Mutex.new` is not atomic: two first callers can each allocate
# their own and exclude nothing. The mutex is created when DefinitionMethods
# is extended (Horreum.inherited), so a class never observes it nil.
klass = Class.new(Familia::Horreum)
eager = klass.instance_variable_get(:@related_fields_mutex)
[eager.class, eager.equal?(klass.related_fields_mutex), eager.name]
#=> [Familia::ThreadSafety::InstrumentedMutex, true, 'related_fields']

## 19b. Each class in a hierarchy has its own mutex and its own class-level cache
[Rfl428Child.related_fields_mutex.equal?(Rfl428Parent.related_fields_mutex),
 Rfl428Child.class_related_field_cache.equal?(Rfl428Parent.class_related_field_cache),
 Rfl428Child.class_related_field_cache.class]
#=> [false, false, Hash]

## 19c. Concurrent first callers all get the same mutex object
klass = Class.new(Familia::Horreum)
seen = Array.new(8)
latch = Queue.new
threads = 8.times.map do |i|
  Thread.new do
    latch.pop
    seen[i] = klass.related_fields_mutex
  end
end
8.times { latch << true }
threads.each(&:join)
seen.uniq(&:object_id).size
#=> 1

## 20a. A class instance variable with the field's name is not served as the collection
# Configure first so we can also see the lazy build honor it: the eager
# declaration used to overwrite @registry; the lazy one must not read it.
Rfl428Preexisting.configure_related_field(:registry, max_length: 8)
@pre_built = Rfl428Preexisting.registry
[@pre_built.class, @pre_built.max_length, Rfl428Preexisting.instance_variable_get(:@registry)]
#=> [Familia::ListKey, 8, :preexisting]

## 20b. The build went through the lifecycle: definition frozen, repeated access returns the cache
[Rfl428Preexisting.class_related_fields[:registry].opts.frozen?,
 Rfl428Preexisting.registry.equal?(@pre_built),
 Rfl428Preexisting.class_related_field_cache[:registry].equal?(@pre_built)]
#=> [true, true, true]

## 20c. ...so a later configure is refused rather than silently "succeeding" against a dead accessor
Rfl428Preexisting.configure_related_field(:registry, max_length: 9)
#=!> Familia::RelatedFieldFrozenError

## 21a. A custom DataType may read another class-level collection in init during a class-level build
# DataType#initialize (setters + init) runs outside related_fields_mutex;
# holding the non-reentrant lock across it raised ThreadError here.
chain = Rfl428Chain.chain
[chain.class, chain.sibling_dbkey == Rfl428Chain.registry.dbkey,
 Rfl428Chain.class_related_fields[:chain].opts.frozen?,
 Rfl428Chain.class_related_fields[:registry].opts.frozen?]
#=> [Rfl428ChainedList, true, true, true]

## 21b. ...and during an instance-level build (initialize_relatives), with the class-level field untouched so far
[Rfl428ChainInst.class_related_fields[:registry].opts.frozen?,
 Rfl428ChainInst.class_related_field_cache.key?(:registry)]
#=> [false, false]

## 21c. Klass.new builds the custom instance-level type, whose init materializes Klass.registry
inst = Rfl428ChainInst.new(id: "chain-#{@rfl428_run}")
@rfl428_instances << inst
[inst.trail.class, inst.trail.sibling_dbkey == Rfl428ChainInst.registry.dbkey,
 inst.trail.dbkey == Rfl428ChainInst.dbkey(inst.identifier, :trail),
 Rfl428ChainInst.related_fields[:trail].opts.frozen?,
 Rfl428ChainInst.class_related_fields[:registry].opts.frozen?]
#=> [Rfl428ChainedList, true, true, true, true]

## 21d. Cross-thread: a build that re-enters the build lock does not deadlock a concurrent sibling access
# Thread A builds :chain, whose init re-enters the per-class build lock for
# :registry; thread B asks for :registry at the same time and either builds
# it first or waits for A. Both must end on the same :registry object.
chain_a = nil
registry_b = nil
latch = Queue.new
ta = Thread.new { latch.pop; chain_a = Rfl428ChainRace.chain }
tb = Thread.new { latch.pop; registry_b = Rfl428ChainRace.registry }
2.times { latch << true }
finished = [ta, tb].map { |t| t.join(5) }
[finished.none?(&:nil?), chain_a.class, registry_b.equal?(Rfl428ChainRace.registry),
 chain_a.sibling_dbkey == registry_b.dbkey]
#=> [true, Rfl428ChainedList, true, true]

## 22a. Declaring a new field while another thread materializes an instance never raises
# initialize_relatives used to iterate the live registry Hash while
# building; a concurrent, permitted declaration (`klass.list :late_n`,
# as participates_in does at load) then raised RuntimeError "can't add a
# new key into hash during iteration" in the declaring thread. The build
# now iterates a snapshot taken under the mutex. Rfl428SlowBuild keeps
# each SortedSet build (and so the loop) open long enough to collide.
Familia::SortedSet.prepend(Rfl428SlowBuild) unless Familia::SortedSet.ancestors.include?(Rfl428SlowBuild)
Rfl428SlowBuild.active = true
@late_klass = Class.new(Familia::Horreum) do
  identifier_field :id
  field :id
  sorted_set :events, max_length: 10
end
@late_errors = []
begin
  barrier = Queue.new
  ta = Thread.new { barrier.pop; 20.times { |i| @late_klass.new(id: "iter-#{i}") } }
  tb = Thread.new do
    barrier.pop
    20.times do |i|
      @late_klass.list :"late_#{i}"
      Thread.pass
    rescue StandardError => e
      @late_errors << e
    end
  end
  2.times { barrier << true }
  [ta, tb].each(&:join)
ensure
  Rfl428SlowBuild.active = false
end
@late_errors.map { |e| [e.class, e.message] }
#=> []

## 22b. Every late declaration landed; an instance created afterwards builds all of them
inst = @late_klass.new(id: 'iter-after')
[@late_klass.related_fields.size, inst.late_19.class, inst.events.class,
 @late_klass.related_fields[:late_19].opts.frozen?, Rfl428SlowBuild.active]
#=> [21, Familia::ListKey, Familia::SortedSet, true, false]

# Teardown: remove only the keys this file wrote.
Rfl428Registry.registry.delete!
Rfl428SlowBuild.active = false
Rfl428Loaded.dbclient.del(Rfl428Loaded.dbkey(@ld_id)) if @ld_id
@rfl428_instances.each { |inst| inst.destroy! rescue nil }
Familia.members.delete(@late_klass) if @late_klass
@rfl428_classes.each { |klass| delete_test_dbkeys(klass) }
