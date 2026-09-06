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
# lazily. Subclasses get deep-copied definitions. The shared definition Hash
# must never receive an instance-level :parent (that was a race).
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
  Rfl428Concurrent, Rfl428LazyReg, Rfl428Replace,
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

# Teardown: remove only the keys this file wrote.
Rfl428Registry.registry.delete!
Rfl428Registry.dbclient.del(Rfl428Registry.dbkey(@ld_id)) if @ld_id
@rfl428_instances.each { |inst| inst.destroy! rescue nil }
@rfl428_classes.each { |klass| delete_test_dbkeys(klass) }
