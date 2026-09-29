# try/bug_fixes/glob_prefix_key_patterns_try.rb
#
# frozen_string_literal: true

# KEYS and SCAN patterns built from a class prefix, delimiter or suffix used
# those parts verbatim, so a glob character in them widened the match to
# other classes' keys. A class with the prefix "glob_pfx?" counted, listed,
# migrated and indexed the records of a class with the prefix "glob_pfxX",
# and repair_participations! removed members from a rival class's
# collections. A class suffix holding one made all miss the class's own
# records or load another field's key as a record. Every literal part is
# now escaped with Familia.escape_glob; the identifier filter arguments
# stay glob patterns.
#
# The last two testcases cover paths that already dropped foreign keys by
# checking each key's literal prefix after the SCAN. They pin that the
# escaped patterns still find the class's own keys.

require_relative '../support/helpers/test_helpers'
require_relative '../../lib/familia/migration'

# GlobPfxMigration below registers itself; teardown restores the registry.
@initial_migrations = Familia::Migration.migrations.dup

# Class whose prefix holds a glob character.
class ::GlobPfxWidget < Familia::Horreum
  prefix 'glob_pfx?'
  feature :relationships
  identifier_field :wid
  field :wid
  field :email
  set :tags
  unique_index :email, :email_lookup
end

# Rival class whose keys the unescaped "glob_pfx?" prefix matches.
class ::GlobPfxRival < Familia::Horreum
  prefix 'glob_pfxX'
  identifier_field :wid
  field :wid
  field :email
  set :tags
end

# Participation target whose prefix holds a glob character.
class ::GlobPfxTeam < Familia::Horreum
  prefix 'glob_team?'
  feature :relationships
  identifier_field :tid
  field :tid
end

# Rival target with a collection of the same name.
class ::GlobPfxTeamRival < Familia::Horreum
  prefix 'glob_teamX'
  identifier_field :tid
  field :tid
  sorted_set :members
end

# Participant whose audit and repair scan the target's collections.
class ::GlobPfxMember < Familia::Horreum
  feature :relationships
  identifier_field :mid
  field :mid
  participates_in ::GlobPfxTeam, :members
end

# Class whose suffix holds a glob character, with a related field whose
# key suffix the unescaped "obj?" matches.
class ::GlobSfxWidget < Familia::Horreum
  prefix 'glob_sfx'
  suffix 'obj?'
  identifier_field :wid
  field :wid
  hashkey :objx
end

# Class whose suffix holds brackets, which the unescaped pattern reads as
# a character class that its own key does not match.
class ::GlobSfxBracket < Familia::Horreum
  prefix 'glob_sfx_b'
  suffix 'data[v2]'
  identifier_field :wid
  field :wid
end

# Model migration that records the keys it processes.
class ::GlobPfxMigration < Familia::Migration::Model
  self.migration_id = 'glob_pfx_migration'

  class << self
    attr_accessor :processed_keys
  end
  self.processed_keys = []

  def prepare
    @model_class = ::GlobPfxWidget
    @batch_size = 10
  end

  def process_record(_obj, key)
    self.class.processed_keys << key
    track_stat(:records_updated)
  end
end

@cleanup = lambda do
  delete_test_dbkeys('glob_pfx\\?:*', 'glob_pfxX:*', 'glob_team\\?:*', 'glob_teamX:*', 'glob_pfx_member:*')
  delete_test_dbkeys('glob_sfx:*', 'glob_sfx_b:*')
end
@cleanup.call

GlobPfxWidget.new(wid: 'a1', email: 'a1@example.com').save
GlobPfxRival.new(wid: 'a2', email: 'a2@example.com').save
GlobPfxRival.new(wid: 'b1', email: 'b1@example.com').save

## scan_pattern escapes the glob character in the prefix
GlobPfxWidget.scan_pattern
#=> "glob_pfx\\?:*:object"

## dbkey_pattern keeps the identifier glob and escapes the literal parts
[GlobPfxWidget.dbkey_pattern('a*'), GlobPfxWidget.dbkey_pattern('*', 'ta[gs]'), GlobPfxWidget.dbkey_pattern('*', nil)]
#=> ["glob_pfx\\?:a*:object", "glob_pfx\\?:*:ta\\[gs\\]", "glob_pfx\\?:*"]

## dbkey_pattern refuses an empty identifier pattern, like dbkey
begin
  GlobPfxWidget.dbkey_pattern('')
rescue Familia::NoIdentifier => e
  e.class
end
#=> Familia::NoIdentifier

## scan_count and keys_count count only the class's own records
[GlobPfxWidget.scan_count, GlobPfxWidget.keys_count]
#=> [1, 1]

## an identifier filter is still a glob and still stays inside the class
[GlobPfxWidget.scan_count('a*'), GlobPfxWidget.keys_count('a*'), GlobPfxWidget.scan_count('?1')]
#=> [1, 1, 1]

## scan_any? and keys_any? do not see the rival class's records
[GlobPfxWidget.scan_any?('b*'), GlobPfxWidget.keys_any?('b*'), GlobPfxWidget.scan_any?('a*')]
#=> [false, false, true]

## find_keys and all return only the class's own keys
[GlobPfxWidget.find_keys, GlobPfxWidget.all.map(&:wid)]
#=> [["glob_pfx?:a1:object"], ["a1"]]

## all loads only the records of a class whose suffix holds a glob character
@sfx_widget = GlobSfxWidget.new(wid: 's1')
@sfx_widget.save
@sfx_widget.objx['k'] = 'v'
[GlobSfxWidget.all.map(&:dbkey), GlobSfxWidget.all('obj?').map(&:dbkey)]
#=> [["glob_sfx:s1:obj?"], ["glob_sfx:s1:obj?"]]

## all finds the records of a class whose suffix holds brackets
GlobSfxBracket.new(wid: 'b1').save
GlobSfxBracket.all.map(&:dbkey)
#=> ["glob_sfx_b:b1:data[v2]"]

## the counting methods escape a glob character in the class suffix too
[GlobSfxWidget.scan_count, GlobSfxWidget.keys_count, GlobSfxBracket.scan_count, GlobSfxBracket.keys_count]
#=> [1, 1, 1, 1]

## find_keys still reads its suffix argument as a glob
GlobSfxWidget.find_keys('obj*').sort
#=> ["glob_sfx:s1:obj?", "glob_sfx:s1:objx"]

## scan_keys enumerates only the class's own keys
GlobPfxWidget.scan_keys.to_a
#=> ["glob_pfx?:a1:object"]

## the SCAN fallback for a unique index does not index the rival class's records
GlobPfxWidget.email_lookup.clear
count = Familia::Features::Relationships::Indexing::RebuildStrategies.rebuild_via_scan(
  GlobPfxWidget, :email, :add_to_class_email_lookup, GlobPfxWidget.email_lookup
)
[count, GlobPfxWidget.email_lookup.all]
#=> [1, {"a1@example.com"=>"a1"}]

## a model migration scans only the model class's records by default
GlobPfxMigration.processed_keys = []
migration = GlobPfxMigration.new(run: true)
migration.prepare
migration.migrate
[migration.scan_pattern, GlobPfxMigration.processed_keys]
#=> ["glob_pfx\\?:*:object", ["glob_pfx?:a1:object"]]

## audit_participations reports no stale member from a rival class's same-named collection
@team = GlobPfxTeam.new(tid: 't1')
@team.save
@member = GlobPfxMember.new(mid: 'm1')
@member.save
@member.add_to_glob_pfx_team_members(@team)
@rival_team = GlobPfxTeamRival.new(tid: 't2')
@rival_team.save
@rival_team.members.add('rival-member', 1)
GlobPfxMember.audit_participations.flat_map { |result| result[:stale_members] }
#=> []

## repair_participations! leaves the rival class's collection alone
GlobPfxMember.repair_participations!
[@rival_team.members.members, @team.members.members]
#=> [["rival-member"], ["m1"]]

## audit_related_fields still finds the class's own orphaned collection key
GlobPfxWidget.new(wid: 'gone').tags.add('x')
GlobPfxRival.new(wid: 'gone').tags.add('y')
GlobPfxWidget.audit_related_fields.flat_map { |result| result[:orphaned_keys] }
#=> ["glob_pfx?:gone:tags"]

## audit_instances still scans the class's own records and no others
GlobPfxWidget.audit_instances.values_at(:phantoms, :missing)
#=> [[], []]

@cleanup.call
Familia::Migration.migrations.replace(@initial_migrations)
