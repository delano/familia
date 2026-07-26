# try/features/dirty_write_warnings_try.rb
#
# frozen_string_literal: true
#
# Coverage for issue #277: dedupe warn_if_dirty! emissions per dirty window,
# surface a remediation hint in the message, and add the dirty_write_warnings
# class-level mode control (:strict, :warn, :once, :off).
#
# These tests operate on *saved* (dirty-after-save) parents so the warning/dedup
# paths are exercised in isolation. As of #278, mutating a collection on a NEW,
# unsaved dirty parent raises by default (Familia.raise_on_unsaved_parent_write);
# the composition of that raise with this mode control is covered in its own
# section near the bottom.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Captures everything written via Familia.warn during the block by swapping the
# logger (reassigning $stderr does not work -- the logger memoizes its stream).
def capture_familia_warnings
  captured = StringIO.new
  original_logger = Familia.logger
  Familia.logger = Familia::FamiliaLogger.new(captured)
  begin
    yield
  ensure
    Familia.logger = original_logger
  end
  captured.string
end

# Counts how many distinct dirty-write warnings landed in the captured output.
# The phrase appears exactly once per warn call and never in DB-command logs.
def count_dirty_warnings(output)
  output.scan('unsaved scalar fields').length
end

# Uses the global default (:once) -- no explicit class setting.
class DWWDefaultPlan < Familia::Horreum
  identifier_field :planid
  field :planid
  field :name
  field :region
  set :features
end

class DWWOncePlan < Familia::Horreum
  dirty_write_warnings :once
  identifier_field :planid
  field :planid
  field :name
  field :region
  set :features
  hashkey :limits
end

class DWWWarnPlan < Familia::Horreum
  dirty_write_warnings :warn
  identifier_field :planid
  field :planid
  field :name
  set :features
end

class DWWOffPlan < Familia::Horreum
  dirty_write_warnings :off
  identifier_field :planid
  field :planid
  field :name
  set :features
end

class DWWStrictPlan < Familia::Horreum
  dirty_write_warnings :strict
  identifier_field :planid
  field :planid
  field :name
  set :features
end

# Inheritance fixtures
class DWWBasePlan < Familia::Horreum
  dirty_write_warnings :off
  identifier_field :planid
  field :planid
  field :name
  set :features
end

class DWWSubPlan < DWWBasePlan; end

class DWWSubOverridePlan < DWWBasePlan
  dirty_write_warnings :warn
end

# Known clean baseline for the global-state tests
Familia.strict_write_order = false
Familia.dirty_write_warnings = :once
Familia.raise_on_unsaved_parent_write = true

# ---------------------------------------------------------------------------
# Class-level setting resolution
# ---------------------------------------------------------------------------

## A class without an explicit setting resolves to the global default (:once)
DWWDefaultPlan.dirty_write_warnings
#=> :once

## An explicit class setting is reported back
DWWOncePlan.dirty_write_warnings
#=> :once

## :warn class reports :warn
DWWWarnPlan.dirty_write_warnings
#=> :warn

## A subclass inherits the parent class setting through the chain
DWWSubPlan.dirty_write_warnings
#=> :off

## A subclass can override the inherited setting
DWWSubOverridePlan.dirty_write_warnings
#=> :warn

## Class-level setter rejects invalid modes
begin
  DWWDefaultPlan.dirty_write_warnings :nonsense
  :no_raise
rescue ArgumentError => e
  e.message.include?('must be one of')
end
#=> true

## Global setter rejects invalid modes
begin
  Familia.dirty_write_warnings = :nonsense
  :no_raise
rescue ArgumentError => e
  e.message.include?('must be one of')
end
#=> true

# ---------------------------------------------------------------------------
# :once (default) -- dedup per dirty window (saved/dirty-after-save parents)
# ---------------------------------------------------------------------------

## :once mode warns once across repeated writes with the same dirty signature
@p1 = DWWOncePlan.new(planid: 'once1', name: 'A')
@p1.save
@p1.name = 'B' # dirty: {name}
@out1 = capture_familia_warnings do
  @p1.features.add('x')
  @p1.features.add('y')
  @p1.features.add('z')
end
count_dirty_warnings(@out1)
#=> 1

## The single emitted warning carries the remediation hint
@out1.include?('(call #save first or wrap in atomic_write)')
#=> true

## The warning names the unsaved field(s)
@out1.include?('name')
#=> true

## :once mode re-warns when the dirty signature grows (genuinely new info)
@p2 = DWWOncePlan.new(planid: 'once2', name: 'A', region: 'X')
@p2.save
@out2 = capture_familia_warnings do
  @p2.name = 'B'          # dirty {name}
  @p2.features.add('a')   # warn (sig [name])
  @p2.features.add('a2')  # deduped
  @p2.region = 'Y'        # dirty {name, region}
  @p2.features.add('b')   # warn (sig [name, region])
  @p2.features.add('b2')  # deduped
end
count_dirty_warnings(@out2)
#=> 2

## Writes across different DataTypes on one parent share the dedup table
@p3 = DWWOncePlan.new(planid: 'once3', name: 'A')
@p3.save
@p3.name = 'B' # dirty {name}
@out3 = capture_familia_warnings do
  @p3.features.add('x')   # warn (sig [name])
  @p3.limits['cap'] = '5' # same signature -> deduped despite different DataType
end
count_dirty_warnings(@out3)
#=> 1

## Blanket clear_dirty! resets the dedup window so the same signature warns again
@p4 = DWWOncePlan.new(planid: 'once4', name: 'A')
@p4.save
@out4 = capture_familia_warnings do
  @p4.name = 'B'
  @p4.features.add('a')   # warn (sig [name])
  @p4.features.add('a2')  # deduped
  @p4.clear_dirty!        # clears dirty AND resets dedup window
  @p4.name = 'C'          # dirty {name} again
  @p4.features.add('b')   # warns again -- window was reset
end
count_dirty_warnings(@out4)
#=> 2

## Partial clear_dirty! also resets the dedup window
@p5 = DWWOncePlan.new(planid: 'once5', name: 'A', region: 'X')
@p5.save
@out5 = capture_familia_warnings do
  @p5.name = 'B'
  @p5.region = 'Y'         # dirty {name, region}
  @p5.features.add('a')    # warn (sig [name, region])
  @p5.features.add('a2')   # deduped
  @p5.clear_dirty!(:region) # partial clear -> dirty {name}, window reset
  @p5.features.add('b')    # warns (sig [name])
end
count_dirty_warnings(@out5)
#=> 2

## record_dirty_warning! returns true the first time a signature is seen
@rp = DWWOncePlan.new(planid: 'rec1', name: 'A')
@rp.name = 'B'
@sig = @rp.dirty_fields.sort.freeze
@rp.record_dirty_warning!(@sig)
#=> true

## record_dirty_warning! returns false for an already-seen signature
@rp.record_dirty_warning!(@sig)
#=> false

# ---------------------------------------------------------------------------
# :warn -- legacy every-write behavior
# ---------------------------------------------------------------------------

## :warn mode emits a warning on every collection write
@w1 = DWWWarnPlan.new(planid: 'warn1', name: 'A')
@w1.save
@w1.name = 'B'
@out_w = capture_familia_warnings do
  @w1.features.add('x')
  @w1.features.add('y')
  @w1.features.add('z')
end
count_dirty_warnings(@out_w)
#=> 3

## :warn mode still includes the remediation hint
@out_w.include?('(call #save first or wrap in atomic_write)')
#=> true

# ---------------------------------------------------------------------------
# :off -- suppressed for the class
# ---------------------------------------------------------------------------

## :off mode suppresses warnings entirely for the class
@o1 = DWWOffPlan.new(planid: 'off1', name: 'A')
@o1.save
@o1.name = 'B'
@out_o = capture_familia_warnings do
  @o1.features.add('x')
  @o1.features.add('y')
end
count_dirty_warnings(@out_o)
#=> 0

# ---------------------------------------------------------------------------
# :strict -- raises for the class even when global strict is off
# ---------------------------------------------------------------------------

## :strict class raises Familia::Problem even when global strict_write_order is off
Familia.strict_write_order = false
@s1 = DWWStrictPlan.new(planid: 'strict1', name: 'A')
@s1.save
@s1.name = 'B'
begin
  @s1.features.add('x')
  @s1.clear_dirty!
  :no_raise
rescue Familia::Problem => e
  [:raised, e.message.include?('unsaved scalar fields'),
   e.message.include?('(call #save first or wrap in atomic_write)')]
end
#=> [:raised, true, true]

# ---------------------------------------------------------------------------
# Global strict_write_order raises every class EXCEPT those explicitly :off
# ---------------------------------------------------------------------------

## :off overrides even global strict_write_order -- off means off, the class
## mode is the most specific signal and wins over the global escalation
Familia.strict_write_order = true
@go = DWWOffPlan.new(planid: 'goff1', name: 'A')
@go.save
@go.name = 'B'
@go_out = begin
  capture_familia_warnings { @go.features.add('x') }
ensure
  Familia.strict_write_order = false
  @go.clear_dirty!
end
count_dirty_warnings(@go_out)
#=> 0

## Global strict raises on EVERY write (exempt from :once dedup)
Familia.strict_write_order = true
@gd = DWWOncePlan.new(planid: 'gd1', name: 'A')
@gd.save
@gd.name = 'B'
@gd_raises = 0
2.times do
  @gd.features.add('x')
rescue Familia::Problem
  @gd_raises += 1
end
Familia.strict_write_order = false
@gd.clear_dirty!
@gd_raises
#=> 2

# ---------------------------------------------------------------------------
# Global default fallback
# ---------------------------------------------------------------------------

## Familia.dirty_write_warnings = :off silences a class with no own setting
Familia.dirty_write_warnings = :off
DWWDefaultPlan.dirty_write_warnings
#=> :off

## ...and that suppression is observable on a collection write
@gf = DWWDefaultPlan.new(planid: 'gf1', name: 'A')
@gf.save
@gf.name = 'B'
@out_gf = capture_familia_warnings do
  @gf.features.add('x')
end
Familia.dirty_write_warnings = :once # restore before the assertion
count_dirty_warnings(@out_gf)
#=> 0

## A class with its own explicit setting ignores the global override
DWWOncePlan.dirty_write_warnings
#=> :once

## Restoring the global default flows back to fallback classes
Familia.dirty_write_warnings = :once
DWWDefaultPlan.dirty_write_warnings
#=> :once

# ---------------------------------------------------------------------------
# atomic_write suppression takes priority over all modes (including :strict)
# ---------------------------------------------------------------------------

## atomic_write suppresses the warning/raise even for a :strict class
Familia.strict_write_order = false
@aw = DWWStrictPlan.new(planid: 'aw1', name: 'A')
@aw.save
@aw_result = @aw.atomic_write do
  @aw.name = 'Dirty'      # makes parent dirty by design
  @aw.features.add('x')   # would raise in :strict, but suppressed inside the block
end
@aw_result
#=> true

## ...and no warning text leaked while inside the atomic_write block
@aw2 = DWWStrictPlan.new(planid: 'aw2', name: 'A')
@aw2.save
@out_aw = capture_familia_warnings do
  @aw2.atomic_write do
    @aw2.name = 'Dirty'
    @aw2.features.add('y')
  end
end
count_dirty_warnings(@out_aw)
#=> 0

# ---------------------------------------------------------------------------
# Composition with #278: new, unsaved parent raise-by-default
#
# For a NON-off class the raise paths (strict_write_order, class :strict, and
# #278's new-object safety raise) fire independently of the warn mode -- so a
# :once/:warn class still raises on a new, unsaved parent by default. But an
# explicit :off is authoritative for the class ("off means off") and overrides
# every raise switch; Familia.raise_on_unsaved_parent_write only matters for
# classes that have NOT opted out.
# ---------------------------------------------------------------------------

## raise_on_unsaved_parent_write defaults to true
Familia.raise_on_unsaved_parent_write
#=> true

## A new, unsaved :once parent RAISES by default (safety raise wins over warn mode)
@ni = DWWOncePlan.new(planid: 'newonce', name: 'A')
@ni.name = 'B' # dirty, never saved
@ni_outcome = begin
  @ni.features.add('x')
  :no_raise
rescue Familia::Problem => e
  [:raised, e.message.include?('new, unsaved object'),
   e.message.include?('(call #save first or wrap in atomic_write)')]
ensure
  @ni.clear_dirty!
end
@ni_outcome
#=> [:raised, true, true]

## A new, unsaved :off parent is suppressed entirely -- off means off (no warn, no raise)
@nf = DWWOffPlan.new(planid: 'newoff', name: 'A')
@nf.name = 'B'
@nf_out = begin
  capture_familia_warnings { @nf.features.add('x') }
ensure
  @nf.clear_dirty!
end
count_dirty_warnings(@nf_out)
#=> 0

## raise_on_unsaved_parent_write=false: a new unsaved :once parent warns, deduped, new-object message
Familia.raise_on_unsaved_parent_write = false
@nw = DWWOncePlan.new(planid: 'newwarn', name: 'A')
@nw.name = 'B'
@nw_out = begin
  capture_familia_warnings do
    @nw.features.add('x')
    @nw.features.add('y') # deduped (same dirty signature)
  end
ensure
  Familia.raise_on_unsaved_parent_write = true
  @nw.clear_dirty!
end
[count_dirty_warnings(@nw_out), @nw_out.include?('new, unsaved object')]
#=> [1, true]

# @nf (above) already proved :off suppresses a new unsaved parent with
# raise_on_unsaved_parent_write at its default (true). Together with this case
# (raise_on_unsaved_parent_write = false), :off is shown to suppress regardless
# of the safety switch -- the class mode is authoritative either way.

## :off suppresses a new unsaved parent independent of raise_on_unsaved_parent_write
Familia.raise_on_unsaved_parent_write = false
@no = DWWOffPlan.new(planid: 'newoff2', name: 'A')
@no.name = 'B'
@no_out = begin
  capture_familia_warnings { @no.features.add('x') }
ensure
  Familia.raise_on_unsaved_parent_write = true
  @no.clear_dirty!
end
count_dirty_warnings(@no_out)
#=> 0

## Teardown
Familia.strict_write_order = false
Familia.dirty_write_warnings = :once
Familia.raise_on_unsaved_parent_write = true
Familia.dbclient.flushdb
