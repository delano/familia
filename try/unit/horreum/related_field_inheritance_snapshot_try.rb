# try/unit/horreum/related_field_inheritance_snapshot_try.rb
#
# frozen_string_literal: true

require 'timeout'

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Blocks while inherited deep-copies one definition so the test can mutate the
# parent's live registry at a deterministic point in the copy.
class RfisBlockingDupOptions < Hash
  def initialize(control)
    @control = control
    super()
  end

  def initialize_copy(source)
    super
    return unless @control[:armed].true?

    @control[:armed].make_false
    @control[:entered] << true
    @control[:release].pop
  end
end

def rfis_inherited_copy_race(scope)
  parent = Class.new(Familia::Horreum) do
    identifier_field :id
    field :id
  end
  registry_name, declaration_method, original_name, late_name = if scope == :instance
    [:related_fields, :list, :events, :late_events]
  else
    [:class_related_fields, :class_list, :registry, :late_registry]
  end
  parent.public_send(declaration_method, original_name)

  control = {
    armed: Concurrent::AtomicBoolean.new(false),
    entered: Queue.new,
    release: Queue.new,
  }
  registry = parent.public_send(registry_name)
  definition = registry.fetch(original_name)
  blocking_opts = RfisBlockingDupOptions.new(control)
  blocking_opts.merge!(definition.opts)
  parent.related_fields_mutex.synchronize do
    registry[original_name] = definition.with(opts: blocking_opts)
  end
  control[:armed].make_true

  child = nil
  inherited_error = nil
  declaration_error = nil
  inheritor = Thread.new do
    child = Class.new(parent)
  rescue StandardError => e
    inherited_error = e
  end

  begin
    Timeout.timeout(5) { control[:entered].pop }
    declarer = Thread.new do
      parent.public_send(declaration_method, late_name)
    rescue StandardError => e
      declaration_error = e
    end
    declarer.join
  rescue Timeout::Error => e
    inherited_error ||= e
  ensure
    control[:release] << true
    inheritor.join
  end

  {
    parent: parent,
    child: child,
    registry_name: registry_name,
    original_name: original_name,
    late_name: late_name,
    inherited_error: inherited_error,
    declaration_error: declaration_error,
  }
end

## Subclass copying tolerates a concurrent instance-field declaration
# The blocking options pause the deep copy after inherited has taken its
# registry snapshot. Before the snapshot fix, mutating the live Hash here raised
# "can't add a new key into hash during iteration" in the declaring thread.
@rfis_instance = rfis_inherited_copy_race(:instance)
@rfis_classes = [@rfis_instance[:parent], @rfis_instance[:child]]
instance_parent_fields = @rfis_instance[:parent].related_fields
instance_child_fields = @rfis_instance[:child]&.related_fields
[
  @rfis_instance[:inherited_error]&.class,
  @rfis_instance[:declaration_error]&.class,
  instance_parent_fields.key?(@rfis_instance[:late_name]),
  instance_child_fields&.key?(@rfis_instance[:original_name]),
  instance_child_fields&.key?(@rfis_instance[:late_name]),
]
#=> [nil, nil, true, true, false]

## Subclass copying tolerates a concurrent class-field declaration
@rfis_class = rfis_inherited_copy_race(:class)
@rfis_classes.push(@rfis_class[:parent], @rfis_class[:child])
class_parent_fields = @rfis_class[:parent].class_related_fields
class_child_fields = @rfis_class[:child]&.class_related_fields
[
  @rfis_class[:inherited_error]&.class,
  @rfis_class[:declaration_error]&.class,
  class_parent_fields.key?(@rfis_class[:late_name]),
  class_child_fields&.key?(@rfis_class[:original_name]),
  class_child_fields&.key?(@rfis_class[:late_name]),
]
#=> [nil, nil, true, true, false]

# Teardown
@rfis_classes.each { |klass| Familia.members.delete(klass) if klass }
