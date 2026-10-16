# try/bug_fixes/multi_index_blank_value_other_index_try.rb
#
# frozen_string_literal: true

# The key "<scope key>:<index>" that the factories name for a blank value
# can be a bucket of another index of the scope class: of another
# instance-scoped index within the scope class, for a scope whose
# identifier is "<other scope>:<other index>:<value>" or
# "<other scope>:<other index>", and of a class-level index of the scope
# class, for a scope whose identifier is "<class index>" or starts with
# "<class index>:". The indexing guide's cleanup of a legacy blank-value key
# checks every index name of the scope class before a DEL, and rebuilds or
# SREMs such a key instead.

require_relative '../support/helpers/test_helpers'

# Scope class with a class-level index of its own.
class ::BoTeam < Familia::Horreum
  feature :relationships
  identifier_field :tid
  field :tid
  field :region
  multi_index :region, :region_index
end

# Two instance-scoped indexes within BoTeam.
class ::BoMember < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  field :desk
  field :seat
  multi_index :desk, :desk_index, within: ::BoTeam
  multi_index :seat, :seat_index, within: ::BoTeam
  participates_in ::BoTeam, :members
end

# The guide's checks before a DEL of the blank-value desk_index key of +id+.
def bo_cleanup_checks(id)
  d = Familia.delim
  scoped = Familia.multi_indexes(class_level: false).select { |idx| idx.scope_class == BoTeam }
  own = Familia.multi_indexes(class_level: true, owner: BoTeam)
  [
    BoTeam.related_fields.key?(:desk_index),
    scoped.none? { |idx| "#{id}#{d}".include?("#{d}#{idx.index_name}#{d}") },
    own.none? { |idx| "#{id}#{d}".start_with?("#{idx.index_name}#{d}") },
  ]
end

@client = Familia.dbclient
delete_test_dbkeys(BoTeam, BoMember)

@team = BoTeam.new(tid: 't-1', region: 'eu')
@team.save
@x_seat = BoMember.new(mid: 'm1', desk: 'north', seat: 'x:desk_index')
@x_seat.save
@x_seat.add_to_bo_team_members(@team)
@x_seat.add_to_bo_team_seat_index(@team)
@named_seat = BoMember.new(mid: 'm2', desk: 'north', seat: 'desk_index')
@named_seat.save
@named_seat.add_to_bo_team_members(@team)
@named_seat.add_to_bo_team_seat_index(@team)

## The guide's checks pass for a scope identifier that names no bucket
bo_cleanup_checks('t-1')
#=> [false, true, true]

## The blank-value key of "<scope>:<other index>:<value>" is that index's bucket of "<value>:<index>"
@long_team = BoTeam.new(tid: 't-1:seat_index:x')
@long_team.save
@long_key = @long_team.desk_index_for('').dbkey
@client.sadd(@long_key, %w[m8 m9])
[
  @long_key,
  @team.seat_index_for('x:desk_index').dbkey == @long_key,
  @long_team.tid.include?("#{Familia.delim}desk_index#{Familia.delim}"),
  bo_cleanup_checks(@long_team.tid),
  @client.smembers(@long_key).sort,
]
#=> ["bo_team:t-1:seat_index:x:desk_index", true, false, [false, false, true], ["m1", "m8", "m9"]]

## The seat_index audit reads that key as the shorter scope's bucket
@seat_audit = BoMember.audit_multi_indexes.find { |result| result[:index_name] == :seat_index }
@seat_audit[:stale_members].map { |entry| entry.values_at(:indexed_id, :reason, :scope_id) }.sort_by(&:first)
#=> [["m8", :object_missing, "t-1"], ["m9", :object_missing, "t-1"]]

## The documented SREM keeps the members whose seat is the bucket's value
@stray = @client.smembers(@long_key).reject { |id| BoMember.load(id)&.seat == 'x:desk_index' }
@client.srem(@long_key, @stray) unless @stray.empty?
[@stray.sort, @client.smembers(@long_key), @team.find_all_by_seat('x:desk_index').map(&:mid)]
#=> [["m8", "m9"], ["m1"], ["m1"]]

## The shorter scope's seat_index rebuild replaces the key's members with that scope's objects
@client.sadd(@long_key, %w[m8 m9])
@team.rebuild_seat_index
[@client.smembers(@long_key), @team.find_all_by_seat('x:desk_index').map(&:mid)]
#=> [["m1"], ["m1"]]

## The blank-value key of "<scope>:<other index>" is that index's bucket of "<index>"
@tail_team = BoTeam.new(tid: 't-1:seat_index')
@tail_team.save
@tail_key = @tail_team.desk_index_for('').dbkey
@client.sadd(@tail_key, 'm8')
@team.rebuild_seat_index
[
  @tail_key,
  @team.seat_index_for('desk_index').dbkey == @tail_key,
  bo_cleanup_checks(@tail_team.tid),
  @client.smembers(@tail_key),
]
#=> ["bo_team:t-1:seat_index:desk_index", true, [false, false, true], ["m2"]]

## The blank-value key of a scope named like a class-level index of the scope class is that index's bucket
@region_team = BoTeam.new(tid: 'region_index', region: 'eu')
@region_team.save
@far_team = BoTeam.new(tid: 't-9', region: 'desk_index')
@far_team.save
BoTeam.rebuild_region_index
@region_key = @region_team.desk_index_for('').dbkey
@client.sadd(@region_key, 'm8')
[
  @region_key,
  BoTeam.region_index_for('desk_index').dbkey == @region_key,
  bo_cleanup_checks(@region_team.tid),
  bo_cleanup_checks('region_index:w'),
  @client.smembers(@region_key).sort,
]
#=> ["bo_team:region_index:desk_index", true, [false, true, false], [false, true, false], ["m8", "t-9"]]

## The region_index audit reads that key as its bucket, and the class rebuild keeps only the team with that region
@region_audit = BoTeam.audit_multi_indexes.find { |result| result[:index_name] == :region_index }
@region_stale = @region_audit[:stale_members].map { |entry| entry[:indexed_id] }
BoTeam.rebuild_region_index
[@region_stale, @client.smembers(@region_key), BoTeam.find_all_by_region('desk_index').map(&:tid)]
#=> [["m8"], ["t-9"], ["t-9"]]

# Teardown
delete_test_dbkeys(BoTeam, BoMember)
