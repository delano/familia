# try/bug_fixes/invalid_scope_id_index_tracker_try.rb
#
# frozen_string_literal: true

# An instance-scoped index records each membership in the indexed record's
# _idx_scopes tracker, under a tab-separated entry holding the scope
# identifier and, for a multi_index, the field value. The entry was built
# by string interpolation. With a scope identifier that is not valid UTF-8
# in a BINARY String and a non-ASCII field value such as 'rôle',
# interpolation raised Encoding::CompatibilityError:
#
# - add_to_<scope>_<index> raised after the SADD, so the bucket held the
#   record but the tracker did not, and destroy! left the member behind;
# - destroy! and save rebuild the scope from the tracker entry read back,
#   which the client returns as BINARY, so they raised for a scope
#   identifier given as UTF-8 with invalid bytes too, before removing or
#   saving anything.
#
# The entry is now built as bytes, in the encoding
# Familia.normalize_key_encoding gives them.

require_relative '../support/helpers/test_helpers'

class ::TrackedScopeLeague < Familia::Horreum
  feature :relationships

  prefix 'ligue_suivie'
  identifier_field :lid
  field :lid
end

class ::TrackedScopeTeam < Familia::Horreum
  feature :relationships

  identifier_field :tid
  field :tid
  field :division
  field :badge

  multi_index :division, :division_index, within: TrackedScopeLeague
  unique_index :badge, :badge_index, within: TrackedScopeLeague
end

@cleanup = lambda do
  [TrackedScopeLeague, TrackedScopeTeam].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

# Keys left under the league and team prefixes other than the leagues'
# hashes and the instances timelines.
@leftover_keys = lambda do
  league_keys = TrackedScopeLeague.dbclient.scan_each(match: 'ligue_suivie:*').map(&:b)
  team_keys = TrackedScopeTeam.dbclient.scan_each(match: 'tracked_scope_team:*').map(&:b)
  (league_keys + team_keys).reject { |key| key.end_with?(':object'.b, ':instances'.b) && key.start_with?('ligue_suivie:'.b) }.sort
end

@binary_league = TrackedScopeLeague.new(lid: "bin\xFE".b)
@binary_league.save
@team_a = TrackedScopeTeam.new(tid: 'team-a', division: 'rôle', badge: 'nº7')
@team_a.save

## add_to_* with a BINARY scope identifier and a non-ASCII value records the tracker entry
@team_a.add_to_tracked_scope_league_division_index(@binary_league)
@team_a.read_instance_index_scopes
#=> {"tracked_scope_league\tdivision_index\tbin\xFE\trôle".b => 'rôle'}

## the unique index records its entry too
@team_a.add_to_tracked_scope_league_badge_index(@binary_league)
@team_a.read_instance_index_scopes.keys.sort
#=> ["tracked_scope_league\tbadge_index\tbin\xFE".b, "tracked_scope_league\tdivision_index\tbin\xFE\trôle".b]

## find_all_by_division and find_by_badge find the team in the league
[@binary_league.find_all_by_division('rôle').map(&:tid), @binary_league.find_by_badge('nº7')&.tid]
#=> [['team-a'], 'team-a']

## destroy! on a loaded copy removes the team from both indexes and leaves no keys
TrackedScopeTeam.find_by_id('team-a').destroy!
[@binary_league.find_all_by_division('rôle'), @binary_league.find_by_badge('nº7'), @leftover_keys.call]
#=> [[], nil, []]

## a scope identifier given as UTF-8 with invalid bytes is indexed and tracked
@utf8_league = TrackedScopeLeague.new(lid: "inv\xFF")
@utf8_league.save
@team_b = TrackedScopeTeam.new(tid: 'team-b', division: 'rôle', badge: 'nº8')
@team_b.save
@team_b.add_to_tracked_scope_league_division_index(@utf8_league)
@team_b.add_to_tracked_scope_league_badge_index(@utf8_league)
@team_b.read_instance_index_scopes.keys.sort
#=> ["tracked_scope_league\tbadge_index\tinv\xFF".b, "tracked_scope_league\tdivision_index\tinv\xFF\trôle".b]

## save refreshes the tracked indexes from the tracker entries read back
@team_b.division = 'élite'
@team_b.badge = 'nº9'
@team_b.save
[@utf8_league.find_all_by_division('élite').map(&:tid), @utf8_league.find_by_badge('nº9')&.tid]
#=> [['team-b'], 'team-b']

## destroy! removes every bucket the team was tracked in and leaves no keys
TrackedScopeTeam.find_by_id('team-b').destroy!
[@utf8_league.find_all_by_division('rôle'), @utf8_league.find_all_by_division('élite'), @leftover_keys.call]
#=> [[], [], []]

@cleanup.call
