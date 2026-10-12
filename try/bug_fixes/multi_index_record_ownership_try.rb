# try/bug_fixes/multi_index_record_ownership_try.rb
#
# frozen_string_literal: true

# The multi_index rebuild and audits decide whether a key under a bucket
# prefix belongs to another record (see RecordKeyOwnership). They took a
# record as existing when its hash key existed. With a field value equal
# to the class suffix, the bucket "ro_user:role_index:object" sits at the
# hash key of a record "role_index", which does not exist. So:
#
# - a second value equal to a set field name made the rebuild raise
#   Familia::IndexBucketConflictError, naming that bucket as the owner;
# - a stale bucket of such a value was left in place by the rebuild while
#   the audit and health_check reported the index as healthy;
# - repair_participations! removed the members of a bucket whose value
#   equaled a set collection name.
#
# A record now exists only when its hash key holds a hash. The candidate
# owners of the keys are checked in pipelines of at most
# RecordKeyOwnership::MAX_CANDIDATE_BATCH_BYTES of identifiers, and a key
# with more of them than RecordKeyOwnership::MAX_CANDIDATE_SPLITS is not
# checked: the rebuild raises for it before it deletes anything, and the
# audit reports it.
# repair_multi_indexes! records a rebuild that raises the conflict error
# and goes on with the next scope or index.
#
# Keys are compared as bytes, so a record or scope identifier with invalid
# UTF-8 under a class prefix with non-ASCII characters no longer raises
# Encoding::CompatibilityError in the audits.

require_relative '../support/helpers/test_helpers'

# Class-level multi_indexes on a class with a set field.
class ::RoUser < Familia::Horreum
  feature :relationships
  identifier_field :uid
  field :uid
  field :role
  field :tier
  set :tags
  multi_index :role, :role_index
  multi_index :tier, :tier_index
end

# Scope class with a set field and a class-level multi_index.
class ::RoCo < Familia::Horreum
  feature :relationships
  identifier_field :cid
  field :cid
  field :industry
  set :tags
  multi_index :industry, :industry_index
end

# Instance-scoped multi_index within RoCo.
class ::RoEmp < Familia::Horreum
  feature :relationships
  identifier_field :eid
  field :eid
  field :dept
  multi_index :dept, :dept_index, within: ::RoCo
  participates_in ::RoCo, :staff
end

# Set participation whose name a company industry or a dept can equal.
class ::RoCrew < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  participates_in ::RoCo, :crew, type: :set
end

# Target class whose prefix holds a non-ASCII character.
class ::RoTeam < Familia::Horreum
  prefix 'équipe_ro'
  feature :relationships
  identifier_field :tid
  field :tid
end

# Participant in the teams' member collections.
class ::RoMember < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  participates_in ::RoTeam, :members
end

# Scope class whose prefix holds a non-ASCII character.
class ::RoSquad < Familia::Horreum
  prefix 'équipe_sq'
  feature :relationships
  identifier_field :sid
  field :sid
end

# Instance-scoped multi_index within RoSquad.
class ::RoPlayer < Familia::Horreum
  feature :relationships
  identifier_field :pid
  field :pid
  field :pos
  multi_index :pos, :pos_index, within: ::RoSquad
end

@ownership = Familia::Features::Relationships::Indexing::RecordKeyOwnership
@client = Familia.dbclient
# One DEL per key: a team or squad key with invalid UTF-8 comes back as a binary
# String, which the test command logger cannot join with UTF-8 keys.
@delete_keys = lambda do
  [RoTeam, RoSquad].each do |klass|
    @client.scan_each(match: "#{Familia.escape_glob(klass.key_prefix)}*").to_a.each { |key| @client.del(key) }
  end
  delete_test_dbkeys(RoUser, RoCo, RoEmp, RoCrew, RoMember, RoPlayer)
end
@delete_keys.call

## Class-level: the bucket of value "object" is a set, and no record is named after the index
@u1 = RoUser.new(uid: 'u1', role: 'object')
@u1.save
@u2 = RoUser.new(uid: 'u2', role: 'tags')
@u2.save
RoUser.rebuild_role_index
[
  @client.type('ro_user:role_index:object'),
  @ownership.existing_records(RoUser, %w[role_index u1]),
  @ownership.other_record_key_owner('ro_user:role_index:tags', RoUser),
]
#=> ["set", [false, true], nil]

## Class-level: the rebuild writes the bucket of a value equal to a set field name
[RoUser.rebuild_role_index, RoUser.role_index_for('tags').members, RoUser.role_index_for('object').members]
#=> [2, ["u2"], ["u1"]]

## Class-level: the audit reports a stale member of that bucket
@client.sadd('ro_user:role_index:tags', '"ghost"')
@audit = RoUser.audit_multi_indexes.find { |result| result[:index_name] == :role_index }
[@audit[:status], @audit[:stale_members].map { |entry| entry[:indexed_id] }, RoUser.health_check.healthy?]
#=> [:issues_found, ["ghost"], false]

## Class-level: the rebuild clears that stale member
RoUser.rebuild_role_index
[RoUser.role_index_for('tags').members, RoUser.audit_multi_indexes.map { |result| result[:status] }, RoUser.health_check.healthy?]
#=> [["u2"], [:ok, :ok], true]

## Class-level: a stale bucket of a value equal to a set field name is cleared
@u2.role = 'admin'
@u2.save
RoUser.rebuild_role_index
[RoUser.role_index_for('tags').exists?, RoUser.role_index_for('admin').members]
#=> [false, ["u2"]]

## Instance-scoped: the scope's own "object" bucket is not taken for a record
@c1 = RoCo.new(cid: 'c-1', industry: 'object')
@c1.save
@e1 = RoEmp.new(eid: 'e1', dept: 'object')
@e1.save
@e1.add_to_ro_co_staff(@c1)
@e2 = RoEmp.new(eid: 'e2', dept: 'tags')
@e2.save
@e2.add_to_ro_co_staff(@c1)
[@c1.rebuild_dept_index, @c1.rebuild_dept_index, @c1.dept_index_for('tags').members, @c1.dept_index_for('object').members]
#=> [2, 2, ["e2"], ["e1"]]

## Instance-scoped: the audit reports a stale member of that bucket, and the rebuild clears it
@c1.dept_index_for('tags').add('e-ghost')
@before = RoEmp.audit_multi_indexes.first
@c1.rebuild_dept_index
[
  @before[:status],
  @before[:stale_members].map { |entry| entry[:indexed_id] },
  @c1.dept_index_for('tags').members,
  RoEmp.audit_multi_indexes.first[:status],
]
#=> [:issues_found, ["e-ghost"], ["e2"], :ok]

## A value repeating the delimiter and an index name stops the rebuild within a few round trips
@c5 = RoCo.new(cid: 'c-5')
@c5.save
@long_value = 'x:dept_index:' * 2000
@e6 = RoEmp.new(eid: 'e6', dept: @long_value)
@e6.save
@e6.add_to_ro_co_staff(@c5)
@c5.dept_index_for('old').add('e-old')
@long_key = "ro_co:c-5:dept_index:#{@long_value}"
@commands = DatabaseLogger.capture_commands do
  @c5.rebuild_dept_index
rescue Familia::IndexBucketConflictError => e
  @long_conflict = e
end
[@long_conflict&.conflicts, @commands.size < 5, @c5.dept_index_for('old').members]
#=> [{ @long_key => :too_many_candidate_owners }, true, ["e-old"]]

## The error message says the owner of that key was not checked
@long_conflict.message.include?('(owner not checked: too_many_candidate_owners)')
#=> true

## The audit reports such a bucket without an owner, and health_check counts it
@e6.add_to_ro_co_dept_index(@c5)
@commands = DatabaseLogger.capture_commands { @long_audit = RoEmp.audit_multi_indexes.first }
[
  @long_audit[:status],
  @long_audit[:foreign_owned_keys].map { |entry| entry.values_at(:key, :owner_key, :reason, :scope_id) },
  @commands.count { |entry| entry.command.include?(@long_value) },
  RoEmp.health_check.healthy?,
]
#=> [:issues_found, [[@long_key, nil, :too_many_candidate_owners, "c-5"]], 0, false]

## The rebuild also stops before deleting when such a bucket is stale
@e6.dept = 'ops'
@e6.save
begin
  @c5.rebuild_dept_index
rescue Familia::IndexBucketConflictError => e
  @stale_conflict = e
end
[@stale_conflict&.conflicts, @client.exists(@long_key), @c5.dept_index_for('old').members]
#=> [{ @long_key => :too_many_candidate_owners }, 1, ["e-old"]]

## A set field of another record is reported as foreign-owned and does not count against health
@client.del(@long_key)
@c5.dept_index_for('old').clear
@c5.rebuild_dept_index
@c9 = RoCo.new(cid: 'c-9')
@c9.save
@c9_owner = RoCo.new(cid: 'c-9:dept_index')
@c9_owner.save
@c9_owner.tags.add('keep')
@owned = RoEmp.audit_multi_indexes.first
[
  @owned[:status],
  @owned[:foreign_owned_keys].map { |entry| entry.values_at(:key, :owner_key, :reason, :scope_id) },
]
#=> [:ok, [["ro_co:c-9:dept_index:tags", "ro_co:c-9:dept_index:object", :other_record, "c-9"]]]

## An unchecked stale bucket is the only issue: the audit reports it and health_check counts it
@over_cap_value = 'x:dept_index:' * 20
@c5.dept_index_for(@over_cap_value).add('e6')
@over_cap = RoEmp.audit_multi_indexes.first
[
  @over_cap[:status],
  @over_cap[:missing],
  @over_cap[:stale_members],
  @over_cap[:orphaned_keys],
  @over_cap[:foreign_owned_keys].map { |entry| entry.values_at(:owner_key, :reason, :scope_id) }.sort_by { |entry| entry[1] },
  @c5.find_all_by_dept('ops').map(&:eid),
  RoEmp.health_check.healthy?,
]
#=> [:issues_found, [], [], [], [["ro_co:c-9:dept_index:object", :other_record, "c-9"], [nil, :too_many_candidate_owners, "c-5"]], ["e6"], false]

## Without the unchecked bucket the same index is healthy again
@client.del(@c5.dept_index_for(@over_cap_value).dbkey)
[RoEmp.audit_multi_indexes.first[:status], RoEmp.health_check.healthy?]
#=> [:ok, true]

## Long keys with several candidate owners each are checked in pipelines of bounded size
# Each dept value is about 20 KB and has 8 candidate splits, so the 20
# buckets of company c-7 hold about 3 MB of candidate identifiers.
@c7 = RoCo.new(cid: 'c-7')
@c7.save
@wide = (1..20).map do |num|
  employee = RoEmp.new(eid: "w#{num}", dept: ('A' * 20_000) + num.to_s + (':dept_index' * 8))
  employee.save
  employee.add_to_ro_co_staff(@c7)
  employee
end
# Identifier bytes of each pipeline of TYPE commands on record hash keys.
@identifier_bytes = lambda do |commands|
  commands.filter_map do |entry|
    record_types = entry.command.split(' | ')
    next unless record_types.all? { |command| command.start_with?('type ro_co:') && command.end_with?(':object') }

    record_types.sum { |command| command.delete_prefix('type ro_co:').delete_suffix(':object').bytesize }
  end
end
@rebuild_groups = @identifier_bytes.call(DatabaseLogger.capture_commands { @wide_count = @c7.rebuild_dept_index })
@audit_groups = @identifier_bytes.call(DatabaseLogger.capture_commands { @wide_audit = RoEmp.audit_multi_indexes.first })
@limit = @ownership::MAX_CANDIDATE_BATCH_BYTES
[
  @wide_count,
  @c7.find_all_by_dept(@wide.first.dept).map(&:eid),
  @wide_audit[:status],
  @rebuild_groups.sum > 2 * @limit,
  @rebuild_groups.size > 2 && @rebuild_groups.max <= @limit,
  @audit_groups.sum > 2 * @limit,
  @audit_groups.size > 2 && @audit_groups.max <= @limit,
]
#=> [20, ["w1"], :ok, true, true, true, true]

## Removing those employees and their company leaves no keys of c-7
@wide.each(&:destroy!)
@c7.destroy!
@client.scan_each(match: 'ro_co:c-7:*').to_a.each { |key| @client.del(key) }
[@client.scan_each(match: 'ro_co:c-7:*').to_a, RoEmp.audit_multi_indexes.first[:status]]
#=> [[], :ok]

## A class-level set field of a record named after the index is reported the same way
@u1.role = 'admin'
@u1.save
RoUser.rebuild_role_index
@role_owner = RoUser.new(uid: 'role_index', role: 'member')
@role_owner.save
@role_owner.tags.add('keep')
RoUser.rebuild_role_index
@class_owned = RoUser.audit_multi_indexes.find { |result| result[:index_name] == :role_index }
[@class_owned[:status], @class_owned[:foreign_owned_keys].map { |entry| entry.values_at(:key, :owner_key, :reason) }]
#=> [:ok, [["ro_user:role_index:tags", "ro_user:role_index:object", :other_record]]]

## Set participation: buckets named like the collection are not audited as collections
@c2 = RoCo.new(cid: 'c-2', industry: 'crew')
@c2.save
RoCo.rebuild_industry_index
@e3 = RoEmp.new(eid: 'e3', dept: 'crew')
@e3.save
@e3.add_to_ro_co_staff(@c1)
@c1.rebuild_dept_index
@m1 = RoCrew.new(mid: 'm1')
@m1.save
@m1.add_to_ro_co_crew(@c1)
[
  @client.type('ro_co:industry_index:crew'),
  @client.type('ro_co:c-1:dept_index:crew'),
  RoCrew.audit_participations.flat_map { |result| result[:stale_members] },
]
#=> ["set", "set", []]

## Set participation: repair_participations! leaves both buckets intact
[
  RoCrew.repair_participations!,
  RoCo.find_all_by_industry('crew').map(&:cid),
  @c1.find_all_by_dept('crew').map(&:eid),
  @c1.crew.members,
]
#=> [{ stale_removed: 0 }, ["c-2"], ["e3"], ["m1"]]

## Set participation: the indexes still rebuild afterwards
[RoCo.rebuild_industry_index, @c1.rebuild_dept_index, RoCo.find_all_by_industry('crew').map(&:cid)]
#=> [5, 3, ["c-2"]]

## Set participation: a stale member of a real collection is still reported and removed
@m_ghost = RoCrew.new(mid: 'm-ghost')
@m_ghost.save
@m_ghost.add_to_ro_co_crew(@c1)
@client.del(@m_ghost.dbkey)
@stale = RoCrew.audit_participations.flat_map { |result| result[:stale_members] }
[@stale.map { |entry| entry[:collection_key] }, RoCrew.repair_participations!, @c1.crew.members]
#=> [["ro_co:c-1:crew"], { stale_removed: 1 }, ["m1"]]

## Instance-scoped audit: a class-level bucket of the scope class is not read as a scope's bucket
# "ro_co:industry_index:dept_index:x" parses as the "x" bucket of scope
# "industry_index", and the bucket of industry "object" sits at the hash
# key of that scope. The key holds a set, so no such scope exists.
@c6 = RoCo.new(cid: 'c-6', industry: 'dept_index:x')
@c6.save
RoCo.rebuild_industry_index
@scoped_audit = RoEmp.audit_multi_indexes.first
[
  @client.type('ro_co:industry_index:object'),
  @client.type('ro_co:industry_index:dept_index:x'),
  @scoped_audit[:status],
  @scoped_audit[:orphaned_keys],
  @scoped_audit[:stale_members],
  RoEmp.health_check.healthy?,
]
#=> ["set", "set", :ok, [], [], true]

## Removing that company removes its class-level bucket
@c6.destroy!
RoCo.rebuild_industry_index
@client.exists('ro_co:industry_index:dept_index:x')
#=> 0

## audit_participations reads an invalid UTF-8 identifier under a non-ASCII prefix
@team = RoTeam.new(tid: "bad\xFF")
@team.save
@member = RoMember.new(mid: 'rm1')
@member.save
@member.add_to_ro_team_members(@team)
[
  RoMember.audit_participations.flat_map { |result| result[:stale_members] },
  RoMember.repair_participations!,
  RoMember.health_check.participations.size,
]
#=> [[], { stale_removed: 0 }, 1]

## extract_identifier_from_key compares that key as bytes and keeps its encoding
@team_key = @client.scan_each(match: '*:members').find { |key| key.b.start_with?('équipe_ro:'.b) }
@team_id = RoTeam.extract_identifier_from_key(@team_key, 'members')
[@team_key.encoding, @team_id, @team_id == RoTeam.instances.members.first]
#=> [Encoding::ASCII_8BIT, "bad\xFF".b, true]

## The audit of that class matches the identifier with its instances entry
@team_instances = RoTeam.audit_instances
[@team_instances[:phantoms], @team_instances[:missing], RoTeam.health_check.healthy?]
#=> [[], [], true]

## Instance-scoped audit of a scope with an invalid UTF-8 identifier under a non-ASCII prefix
@squad = RoSquad.new(sid: "bad\xFF")
@squad.save
@player = RoPlayer.new(pid: 'p1', pos: 'wing')
@player.save
@squad.pos_index_for('wing').add('p1')
@squad_audit = RoPlayer.audit_multi_indexes.first
[
  @squad_audit[:status],
  @squad_audit[:orphaned_keys],
  @squad_audit[:stale_members],
  @squad_audit[:foreign_owned_keys],
  RoPlayer.health_check.healthy?,
]
#=> [:ok, [], [], [], true]

## repair_multi_indexes! records a conflicting scope and repairs the scopes after it
@c3 = RoCo.new(cid: 'c-3')
@c3.save
@e4 = RoEmp.new(eid: 'e4', dept: 'sales')
@e4.save
@e4.add_to_ro_co_staff(@c3)
@client.set('ro_co:c-3:dept_index:sales', 'not a bucket')
@c4 = RoCo.new(cid: 'c-4')
@c4.save
@e5 = RoEmp.new(eid: 'e5', dept: 'eng')
@e5.save
@e5.add_to_ro_co_staff(@c4)
@repaired = RoEmp.repair_multi_indexes!
[
  @repaired[:rebuilt_per_scope],
  @repaired[:skipped].map { |entry| entry.values_at(:index_name, :scope_id, :reason, :conflicts) },
  @c4.dept_index_for('eng').members,
  @client.get('ro_co:c-3:dept_index:sales'),
]
#=> [[{ index_name: :dept_index, scopes_rebuilt: 6 }], [[:dept_index, "c-3", :bucket_conflict, { "ro_co:c-3:dept_index:sales" => "string" }]], ["e5"], "not a bucket"]

## repair_all! reports the conflict with status :partial_failure
@c4.dept_index_for('eng').clear
@result = RoEmp.repair_all!
[
  @result[:status],
  @result[:errors],
  @result[:multi_indexes][:skipped].map { |entry| entry.values_at(:scope_id, :reason) },
  @c4.dept_index_for('eng').members,
]
#=> [:partial_failure, {}, [["c-3", :bucket_conflict]], ["e5"]]

## repair_multi_indexes! records a conflicting class-level index and rebuilds the next one
@client.del('ro_co:c-3:dept_index:sales')
@c3.rebuild_dept_index
@u3 = RoUser.new(uid: 'u3', role: 'notes', tier: 'gold')
@u3.save
@client.del('ro_user:role_index:notes')
@client.set('ro_user:role_index:notes', 'not a bucket')
@client.sadd('ro_user:tier_index:gold', '"tier-ghost"')
@class_repaired = RoUser.repair_multi_indexes!
[
  @class_repaired[:rebuilt],
  @class_repaired[:skipped].map { |entry| entry.values_at(:index_name, :reason, :conflicts) },
  RoUser.tier_index_for('gold').members,
]
#=> [[:tier_index], [[:role_index, :bucket_conflict, { "ro_user:role_index:notes" => "string" }]], ["u3"]]

@delete_keys.call
