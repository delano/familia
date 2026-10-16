# try/features/relationships/unique_index_fallback_try.rb
#
# frozen_string_literal: true

# Regression coverage for instance-scoped unique-index rebuild fallback
# selection. The backing HashKey points at the indexed class for serialization,
# but it is not a membership collection and must never be sent to
# rebuild_via_participation.

require 'timeout'

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

class UifBlockingLookupOptions < Hash
  def initialize(control)
    @control = control
    super()
  end

  def [](key)
    if key == :record_class && @control[:armed].true?
      @control[:armed].make_false
      @control[:entered] << true
      @control[:release].pop
    end
    super
  end
end

class UniqueIndexFallbackScope < Familia::Horreum
  feature :relationships

  identifier_field :scope_id
  field :scope_id
  list :unrelated
end

class UniqueIndexFallbackRecord < Familia::Horreum
  feature :relationships

  identifier_field :record_id
  field :record_id
  field :badge

  unique_index :badge, :badge_index, within: UniqueIndexFallbackScope
end

delete_test_dbkeys(UniqueIndexFallbackScope, UniqueIndexFallbackRecord)

@uif_control = {
  armed: Concurrent::AtomicBoolean.new(false),
  entered: Queue.new,
  release: Queue.new,
}
@uif_definition = UniqueIndexFallbackScope.related_fields.fetch(:unrelated)
@uif_options = UifBlockingLookupOptions.new(@uif_control)
@uif_options.merge!(@uif_definition.opts)
UniqueIndexFallbackScope.related_fields_mutex.synchronize do
  UniqueIndexFallbackScope.related_fields[:unrelated] =
    @uif_definition.with(opts: @uif_options)
end

@uif_run = Familia.now.to_i.to_s
@uif_scope = UniqueIndexFallbackScope.new(scope_id: "scope-#{@uif_run}")
@uif_scope.save
@uif_record = UniqueIndexFallbackRecord.new(
  record_id: "record-#{@uif_run}",
  badge: "badge-#{@uif_run}",
)
@uif_record.save

## The backing HashKey is not selected as the fallback membership collection
# The scope declares no membership collection for the indexed class, so the
# helper must return nil (Strategy 3 scan) rather than the badge_index HashKey.
@uif_scope.badge_index.clear
selected = Familia::Features::Relationships::Indexing::UniqueIndexGenerators
  .find_membership_collection(@uif_scope, UniqueIndexFallbackRecord, :badge_index)
count = @uif_scope.rebuild_badge_index
[selected, count, @uif_scope.find_by_badge("badge-#{@uif_run}")&.record_id]
#=> [nil, 1, "record-#{@uif_run}"]

## Fallback selection tolerates a concurrent related-field declaration
# Pause the fallback while it inspects the unrelated field. The declaration
# mutates the live registry after rebuild_badge_index has taken its snapshot;
# iterating the live Hash raised "can't add a new key into hash during
# iteration" in the declaring thread.
@uif_scope.badge_index.clear
@uif_control[:armed].make_true
@uif_rebuild_count = nil
@uif_rebuild_error = nil
@uif_declaration_error = nil
@uif_rebuilder = Thread.new do
  @uif_rebuild_count = @uif_scope.rebuild_badge_index
rescue StandardError => e
  @uif_rebuild_error = e
end

begin
  Timeout.timeout(5) { @uif_control[:entered].pop }
  @uif_declarer = Thread.new do
    UniqueIndexFallbackScope.list :late_members
  rescue StandardError => e
    @uif_declaration_error = e
  end
  @uif_declarer.join
rescue Timeout::Error => e
  @uif_rebuild_error ||= e
ensure
  @uif_control[:release] << true
  @uif_rebuilder.join
end
# The late list carries no class: metadata, so after the race the helper
# still selects nothing; the rebuild count came from the scan path.
@uif_selected_after = Familia::Features::Relationships::Indexing::UniqueIndexGenerators
  .find_membership_collection(@uif_scope, UniqueIndexFallbackRecord, :badge_index)
[
  @uif_rebuild_error&.class,
  @uif_declaration_error&.class,
  @uif_rebuild_count,
  UniqueIndexFallbackScope.related_fields.key?(:late_members),
  @uif_selected_after,
]
#=> [nil, nil, 1, true, nil]

# Teardown
@uif_control[:armed].make_false
@uif_control[:release] << true if @uif_rebuilder&.alive?
@uif_rebuilder&.join
@uif_declarer&.join
delete_test_dbkeys(UniqueIndexFallbackScope, UniqueIndexFallbackRecord)
