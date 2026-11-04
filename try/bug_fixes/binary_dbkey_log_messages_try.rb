# try/bug_fixes/binary_dbkey_log_messages_try.rb
#
# frozen_string_literal: true

# Familia.join returns a key whose bytes are not valid UTF-8 as BINARY, the
# encoding redis-client gives the same key. Log and error messages
# interpolated the key next to other text, and a BINARY key with non-ASCII
# bytes raises Encoding::CompatibilityError against non-ASCII UTF-8 text,
# such as a member, a field value or a field name. The messages were built
# even with debug off, so reads of a participation collection with a
# non-ASCII member, rebuilds, audits, commit_fields, HashKey#refresh!, the
# legacy-identifier warning and the structured log entry for a legacy
# field value raised for a scope or record whose identifier is not valid
# UTF-8. Messages now show the key through Familia.loggable_text, which
# returns valid UTF-8 or ASCII-only text, and debug-only messages are built
# only with debug on.

require_relative '../support/helpers/test_helpers'
require 'stringio'

class ::LogMsgTeam < Familia::Horreum
  feature :relationships

  prefix 'logmsg_team'
  identifier_field :tid
  field :tid
end

class ::LogMsgMember < Familia::Horreum
  feature :relationships

  prefix 'logmsg_member'
  identifier_field :mid
  field :mid
  field :grp
  field :badge

  participates_in LogMsgTeam, :members
  multi_index :grp, :grp_index, within: LogMsgTeam
  unique_index :badge, :badge_index, within: LogMsgTeam
end

class ::LogMsgRecord < Familia::Horreum
  prefix 'logmsg_record'
  identifier_field :rid
  field :rid
  field :role
  field :note
  hashkey :prefs
end

class ::LogMsgRel < Familia::Horreum
  prefix 'logmsg_rel'
  identifier_field :rid
  field :rid
  list :rôles
end

@cleanup = lambda do
  [LogMsgTeam, LogMsgMember, LogMsgRecord, LogMsgRel].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

@orig_logger = Familia.logger
@orig_debug = Familia.debug?
@log_io = StringIO.new
Familia.logger = Familia::FamiliaLogger.new(@log_io)

@team = LogMsgTeam.new(tid: "bin\xFE".b)
@team.save
@member = LogMsgMember.new(mid: 'élodie', grp: 'g')
@member.save
@member.add_to_log_msg_team_members(@team)
@member.add_to_log_msg_team_grp_index(@team)
@loaded = LogMsgTeam.find_by_id(LogMsgTeam.instances.members.first)

## Familia.loggable_text returns valid UTF-8 and ASCII-only text as is
[Familia.loggable_text('logmsg:élodie'), Familia.loggable_text('ascii'.b).encoding]
#=> ['logmsg:élodie', Encoding::BINARY]

## Familia.loggable_text writes each byte that is not valid UTF-8 as \xNN
shown = Familia.loggable_text("équipe:bin\xFE".b)
[shown, shown.encoding, "é #{shown}".valid_encoding?]
#=> ["équipe:bin\\xFE", Encoding::UTF_8, true]

## Familia.loggable_text shows non-String values through to_s
[Familia.loggable_text(nil), Familia.loggable_text(:sym), Familia.loggable_text(%w[a b])]
#=> ['', 'sym', '["a", "b"]']

## the loaded scope's participation collection key is BINARY
[@loaded.members.dbkey == "logmsg_team:bin\xFE:members".b, @loaded.members.dbkey.encoding]
#=> [true, Encoding::BINARY]

## members reads a non-ASCII member of the collection
@loaded.members.members
#=> ['élodie']

## each and revrange read it too
seen = []
@loaded.members.each { |member| seen << member }
[seen, @loaded.members.revrange(0, -1)]
#=> [['élodie'], ['élodie']]

## the instance-scoped index rebuilds from the participation collection
@loaded.rebuild_grp_index
#=> 1

## audit_multi_indexes is :ok
LogMsgMember.audit_multi_indexes.map { |result| result[:status] }
#=> [:ok]

## repair_multi_indexes! rebuilds nothing
LogMsgMember.repair_multi_indexes!.slice(:rebuilt, :rebuilt_per_scope)
#=> { rebuilt: [], rebuilt_per_scope: [] }

## health_check is healthy
LogMsgMember.health_check.healthy?
#=> true

## commit_fields writes a non-ASCII value of a record whose identifier is not valid UTF-8
@record = LogMsgRecord.new(rid: "bad\xFF", role: 'rôle')
@record.save
@record.role = 'thé'
@record.commit_fields
LogMsgRecord.find_by_id("bad\xFF").role
#=> 'thé'

## HashKey#refresh! returns a non-ASCII field of that record
@record.prefs['clé'] = 'v'
@record.prefs.refresh!
#=> { 'clé' => 'v' }

## Horreum#refresh! returns a legacy plain-string value of that record
LogMsgRecord.dbclient.hset(@record.dbkey, 'note', 'naïve')
@log_io.truncate(0)
@record.refresh!
@record.note
#=> 'naïve'

## its log entry shows the key with the invalid byte escaped
@log_io.string.include?('key=logmsg_record:bad\xFF:object')
#=> true

## a legacy JSON-encoded entry is read from an index of a scope whose identifier is not valid UTF-8
@legacy_team = LogMsgTeam.new(tid: "bad\xFF")
@legacy_team.save
LogMsgTeam.dbclient.hset(@legacy_team.badge_index.dbkey, 'b1', '"m1"')
LogMsgTeam.dbclient.sadd(@legacy_team.grp_index_for('g').dbkey, '"m1"')
@log_io.truncate(0)
[@legacy_team.badge_index['b1'], @legacy_team.grp_index_for('g').members]
#=> ['m1', ['m1']]

## the warning shows the key with the invalid byte escaped
@log_io.string.include?('Legacy JSON-encoded identifier detected in logmsg_team:bad\xFF:badge_index')
#=> true

## with debug on, find_by_id loads a record whose identifier is not valid UTF-8
Familia.debug = true
begin
  [LogMsgRecord.find_by_id("bad\xFF")&.role, @loaded.members.members]
ensure
  Familia.debug = @orig_debug
end
#=> ['thé', ['élodie']]

## with debug on, destroy! deletes a record with a non-ASCII related field name
LogMsgRel.new(rid: "bad\xFF").save
LogMsgRel.find_by_id("bad\xFF").rôles.push('r')
Familia.debug = true
begin
  [LogMsgRel.find_by_id("bad\xFF").destroy!.successful?, LogMsgRel.dbclient.keys('logmsg_rel:bad*')]
ensure
  Familia.debug = @orig_debug
end
#=> [true, []]

## with debug on, the class-level destroy! deletes it too
LogMsgRel.new(rid: "bad\xFF").save
LogMsgRel.find_by_id("bad\xFF").rôles.push('r')
Familia.debug = true
begin
  [LogMsgRel.destroy!("bad\xFF").successful?, LogMsgRel.dbclient.keys('logmsg_rel:bad*')]
ensure
  Familia.debug = @orig_debug
end
#=> [true, []]

Familia.logger = @orig_logger
Familia.debug = @orig_debug
@cleanup.call
