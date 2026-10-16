# try/bug_fixes/multi_index_blank_value_buckets_try.rb
#
# frozen_string_literal: true

# A multi_index does not index a blank field value (nil, empty or
# whitespace only), whether it is class-level or instance-scoped, and a
# lookup of a blank value returns [].
#
# The factories name the key of a blank value "<owner key>:<index>",
# without the trailing delimiter of every other bucket. That key is not
# exclusive to the index: when the owner declares a related field with the
# index's name, it is that field's key. So no multi_index method reads,
# writes, deletes or audits it, and IndexDescriptor#each_record raises for
# a blank value. The instance-scoped add_to_* used to write
# blank values there; such a key is left for manual cleanup.

require_relative '../support/helpers/test_helpers'

# Scope class with a set field named like the instance-scoped index below.
# It holds member identifiers, as the index buckets do.
class ::BvTeam < Familia::Horreum
  feature :relationships
  identifier_field :tid
  field :tid
  set :pinned, reference: true
end

# The :pinned index shares "<team key>:pinned" with BvTeam's set field.
class ::BvMember < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  field :badge
  field :desk
  multi_index :badge, :pinned, within: ::BvTeam
  multi_index :desk, :desk_index, within: ::BvTeam
  participates_in ::BvTeam, :members
end

# The class-level :featured index shares "bv_user:featured" with the class_set.
class ::BvUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :tier
  class_set :featured, reference: true
  multi_index :tier, :featured
end

@client = Familia.dbclient
delete_test_dbkeys(BvTeam, BvMember, BvUser)

@team = BvTeam.new(tid: 't-1')
@team.save
@blank = BvMember.new(mid: 'm1', badge: '', desk: 'north')
@blank.save
@blank.add_to_bv_team_members(@team)
@spaces = BvMember.new(mid: 'm2', badge: '  ', desk: 'north')
@spaces.save
@spaces.add_to_bv_team_members(@team)
@gold = BvMember.new(mid: 'm3', badge: 'gold', desk: 'south')
@gold.save
@gold.add_to_bv_team_members(@team)
@gold.add_to_bv_team_pinned(@team)
# The team pins members in its own set field.
@team.pinned.add(@blank)
@team.pinned.add(@gold)

## The factory still names the key of a blank value without the trailing delimiter
[@team.pinned_for('').dbkey, @team.pinned_for('  ').dbkey, @team.pinned.dbkey, BvUser.featured_for('').dbkey]
#=> ["bv_team:t-1:pinned", "bv_team:t-1:pinned", "bv_team:t-1:pinned", "bv_user:featured"]

## Instance-scoped add_to_* does not write a blank value into the scope's same-named set
@blank.add_to_bv_team_pinned(@team)
@spaces.add_to_bv_team_pinned(@team)
[@client.smembers('bv_team:t-1:pinned').sort, @team.find_all_by_badge('gold').map(&:mid)]
#=> [["m1", "m3"], ["m3"]]

## add_to_* still tracks the membership of a blank value
[@blank.send(:_index_scope_tracker).hgetall, @spaces.send(:_index_scope_tracker).hgetall]
#=> [{ "bv_team\tpinned\tt-1\t" => '' }, { "bv_team\tpinned\tt-1\t  " => '  ' }]

## So save indexes the object once its value is no longer blank
@spaces.badge = 'silver'
@spaces.save
[@team.find_all_by_badge('silver').map(&:mid), @client.smembers('bv_team:t-1:pinned').sort]
#=> [["m2"], ["m1", "m3"]]

## Instance-scoped find_all_by_* and sample_from_* return [] for a blank value without reading that set
@commands = DatabaseLogger.capture_commands do
  @found = [@team.find_all_by_badge(''), @team.find_all_by_badge('  '), @team.find_all_by_badge(nil),
            @team.sample_from_badge(''), @team.sample_from_badge('  ', 2)]
end
[@found, @commands.count { |entry| entry.command.include?('bv_team:t-1:pinned') }]
#=> [[[], [], [], [], []], 0]

## update_in_* to a blank value leaves the old bucket and adds nothing to the set
@spaces.badge = ''
@spaces.save
@spaces.update_in_bv_team_pinned(@team, 'silver')
[@client.smembers('bv_team:t-1:pinned').sort, @team.find_all_by_badge('silver'), @spaces.send(:_index_scope_tracker).hgetall.values.sort]
#=> [["m1", "m3"], [], ["", "  "]]

## update_in_* from a blank value does not remove the member from the set
@gold.update_in_bv_team_pinned(@team, '')
[@client.smembers('bv_team:t-1:pinned').sort, @team.find_all_by_badge('gold').map(&:mid)]
#=> [["m1", "m3"], ["m3"]]

## remove_from_* with a blank value drops the tracker entry and leaves the set
@blank.remove_from_bv_team_pinned(@team, '')
[@client.smembers('bv_team:t-1:pinned').sort, @blank.send(:_index_scope_tracker).hgetall]
#=> [["m1", "m3"], {}]

## destroy! of a member tracked with a blank value leaves the set
@blank.add_to_bv_team_pinned(@team)
@blank.remove_from_bv_team_members(@team)
@blank.destroy!
[@client.smembers('bv_team:t-1:pinned').sort, @blank.send(:_index_scope_tracker).hgetall]
#=> [["m1", "m3"], {}]

## The scope rebuild leaves the set field named like the index
@cleared = []
@rebuilt = @team.rebuild_pinned { |progress| @cleared << progress[:key] if progress[:key] }
[@rebuilt, @cleared.sort, @client.smembers('bv_team:t-1:pinned').sort, @team.find_all_by_badge('gold').map(&:mid)]
#=> [2, ["bv_team:t-1:pinned:gold"], ["m1", "m3"], ["m3"]]

## The audit does not read the set field as a bucket
@scoped = BvMember.audit_multi_indexes.find { |result| result[:index_name] == :pinned }
@scoped.values_at(:status, :orphaned_keys, :stale_members, :foreign_owned_keys)
#=> [:ok, [], [], []]

## repair_multi_indexes! rebuilds the scope and leaves the set, and health_check is healthy
@team.rebuild_desk_index
@team.pinned_for('bronze').add('m9')
@repaired = BvMember.repair_multi_indexes!
[
  @repaired[:rebuilt_per_scope],
  @client.exists(@team.pinned_for('bronze').dbkey),
  @client.smembers('bv_team:t-1:pinned').sort,
  BvMember.health_check.healthy?,
]
#=> [[{ index_name: :pinned, scopes_rebuilt: 1 }], 0, ["m1", "m3"], true]

## A bucket of another index whose value ends in ":pinned" is not read as a blank-value key
# "bv_team:t-1:desk_index:east:pinned" is the "east:pinned" bucket of
# desk_index. A SCAN for "<scope>*:pinned*" would also match it and read
# it as the "<scope key>:pinned" key of a team "t-1:desk_index:east".
@gold.desk = 'east:pinned'
@gold.save
@team.rebuild_desk_index
@pinned_audit = BvMember.audit_multi_indexes.find { |result| result[:index_name] == :pinned }
[
  @pinned_audit.values_at(:status, :orphaned_keys, :foreign_owned_keys),
  @team.find_all_by_desk('east:pinned').map(&:mid),
  BvMember.health_check.healthy?,
]
#=> [[:ok, [], []], ["m3"], true]

## A key left by an older add_to_* for a blank value is not deleted or audited
# desk_index has no related field of that name on BvTeam, so
# "bv_team:t-1:desk_index" can only have been written for a blank desk.
@client.sadd('bv_team:t-1:desk_index', 'm2')
@team.rebuild_desk_index
[
  BvMember.audit_multi_indexes.find { |result| result[:index_name] == :desk_index }.values_at(:status, :orphaned_keys),
  BvMember.health_check.healthy?,
  @client.smembers('bv_team:t-1:desk_index'),
]
#=> [[:ok, []], true, ["m2"]]

## The documented cleanup is a DEL once the scope class declares no related field of that name
[BvTeam.related_fields.key?(:pinned), BvTeam.related_fields.key?(:desk_index), @client.del('bv_team:t-1:desk_index'), @team.find_all_by_desk('north').map(&:mid)]
#=> [true, false, 1, ["m2"]]

## Class-level: add_to_class_* and update_in_class_* do not touch the same-named class_set
BvUser.featured.add('u1')
BvUser.featured.add('u2')
@u1 = BvUser.new(uid: 'u1', tier: 'pro')
@u1.save
@u2 = BvUser.new(uid: 'u2', tier: '')
@u2.save
@u2.add_to_class_featured
@u1.tier = ''
@u1.update_in_class_featured('pro')
@u1.tier = 'pro'
@u1.update_in_class_featured('')
@u2.remove_from_class_featured
[BvUser.featured.members.sort, BvUser.find_all_by_tier('pro').map(&:uid)]
#=> [["u1", "u2"], ["u1"]]

## Class-level find_all_by_*, sample_from_*, indexed_in? and current_indexings do not read the class_set for a blank value
@commands = DatabaseLogger.capture_commands do
  @found = [
    BvUser.find_all_by_tier(''), BvUser.find_all_by_tier('  '), BvUser.sample_from_tier(''),
    @u2.indexed_in?(:featured), @u2.current_indexings
  ]
end
[@found, @commands.count { |entry| entry.command.include?('bv_user:featured') }]
#=> [[[], [], [], false, []], 0]

## IndexDescriptor#each_record raises for a blank value without reading the same-named set fields
@class_idx = Familia.multi_indexes(owner: BvUser).find { |idx| idx.index_name == :featured }
@scoped_idx = Familia.multi_indexes(owner: BvMember).find { |idx| idx.index_name == :pinned }
@errors = []
@commands = DatabaseLogger.capture_commands do
  [
    -> { @class_idx.each_record(value: '') { |user| user } },
    -> { @class_idx.each_record(value: '  ').to_a },
    -> { @scoped_idx.each_record(value: '', scope: @team) { |member| member } },
    -> { @scoped_idx.each_record(value: "\t", scope: @team).to_a },
  ].each do |call|
    call.call
    @errors << 'no raise'
  rescue ArgumentError => e
    @errors << e.message
  end
end
[
  @errors.uniq,
  @commands.count { |entry| entry.command.include?('bv_user:featured') || entry.command.include?('bv_team:t-1:pinned') },
  BvUser.featured.members.sort,
  @scoped_idx.each_record(value: 'gold', scope: @team).map(&:mid),
]
#=> [["BvUser:featured is a multi_index and does not index a blank value", "BvMember:pinned is a multi_index and does not index a blank value"], 0, ["u1", "u2"], ["m3"]]

## The class-level rebuild leaves the class_set named like the index
@cleared = []
@count = BvUser.rebuild_featured { |progress| @cleared << progress[:key] if progress[:key] }
[@count, @cleared, BvUser.featured.members.sort, BvUser.find_all_by_tier('pro').map(&:uid)]
#=> [2, ["bv_user:featured:pro"], ["u1", "u2"], ["u1"]]

## The class-level audit does not read the class_set, and health_check is healthy
[BvUser.audit_multi_indexes.first.values_at(:status, :orphaned_keys, :stale_members, :foreign_owned_keys), BvUser.health_check.healthy?]
#=> [[:ok, [], [], []], true]

## The class-level audit reports only real buckets, and repair_multi_indexes! leaves the class_set
BvUser.featured_for('gone').add('u9')
@class_audit = BvUser.audit_multi_indexes.first
@repaired = BvUser.repair_multi_indexes!
[
  @class_audit[:orphaned_keys],
  @class_audit[:foreign_owned_keys],
  @repaired[:rebuilt],
  BvUser.featured.members.sort,
  BvUser.audit_multi_indexes.first[:status],
  BvUser.health_check.healthy?,
]
#=> [[{ field_value: 'gone', key: 'bv_user:featured:gone' }], [], [:featured], ["u1", "u2"], :ok, true]

## The rebuild reports only the buckets its DEL removed
# The "gold" bucket and three stale buckets are deleted one per batch.
# While the first is reported, another client deletes one stale bucket that
# is still there, so its DEL removes nothing and it is not reported or
# counted.
@stale_keys = %w[a b c].map { |value| @team.pinned_for(value).dbkey }
@stale_keys.each { |key| @client.sadd(key, 'm9') }
@reported = []
@team.rebuild_pinned(batch_size: 1) do |progress|
  next unless progress[:phase] == :clearing && progress[:key]

  @reported << [progress[:key], progress[:current]]
  @client.del((@stale_keys - [progress[:key]]).first) if @reported.size == 1
end
[
  @reported.size,
  @reported.map(&:last),
  @stale_keys.none? { |key| @client.exists(key).positive? },
  @team.find_all_by_badge('gold').map(&:mid),
  @client.smembers('bv_team:t-1:pinned').sort,
]
#=> [3, [1, 2, 3], true, ["m3"], ["m1", "m3"]]

# Teardown
delete_test_dbkeys(BvTeam, BvMember, BvUser)
