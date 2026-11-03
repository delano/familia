# try/bug_fixes/invalid_scope_id_nested_scope_audit_try.rb
#
# frozen_string_literal: true

# A scope identifier may contain the delimiter. With scopes "inv\xFF" and
# "inv\xFF:division_index:z", the bucket of the longer scope for value
# 'rôle' is "...:inv\xFF:division_index:z:division_index:rôle", which
# parses at the first marker as the bucket of the shorter scope for value
# "z:division_index:rôle". The audit hands such a key to the longer scope
# through RecordKeyOwnership.other_record_keys, which returned that
# scope's identifier and the bucket name in the encoding of the key. The
# key is BINARY because the identifier is not valid UTF-8, so the value
# 'rôle' came back BINARY too, and audit_multi_indexes reported the
# longer scope's member as a stale :value_mismatch and its bucket as a
# :field_value_unheld orphan, which repair_multi_indexes! rebuilt on every
# run. Each part now gets the encoding Familia.normalize_key_encoding gives
# its own bytes.

require_relative '../support/helpers/test_helpers'

class ::NestedScopeFederation < Familia::Horreum
  feature :relationships

  prefix 'nested_scope_fed'
  identifier_field :fid
  field :fid
end

class ::NestedScopeClub < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid
  field :division

  multi_index :division, :division_index, within: NestedScopeFederation
  participates_in NestedScopeFederation, :clubs
end

@cleanup = lambda do
  [NestedScopeFederation, NestedScopeClub].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

["inv\xFF", "inv\xFF:division_index:z"].each_with_index do |fid, idx|
  federation = NestedScopeFederation.new(fid: fid)
  federation.save
  club = NestedScopeClub.new(cid: "club-#{idx}", division: 'rôle')
  club.save
  club.add_to_nested_scope_federation_clubs(federation)
  club.add_to_nested_scope_federation_division_index(federation)
end
@client = NestedScopeFederation.dbclient
@nested_key = "nested_scope_fed:inv\xFF:division_index:z:division_index:rôle".b

## the longer scope's bucket holds its club and comes back BINARY
[@client.smembers(@nested_key), @client.scan_each(match: 'nested_scope_fed:*:division_index:*', type: 'set').to_a.sort == [
  "nested_scope_fed:inv\xFF:division_index:rôle".b, @nested_key,
].sort]
#=> [['club-1'], true]

## the audit of the index is :ok
@result = NestedScopeClub.audit_multi_indexes.first
[@result[:status], @result.fetch(:missing_status, :ok)]
#=> [:ok, :ok]

## nothing is reported stale, missing, orphaned or foreign-owned
[@result[:stale_members], @result[:missing], @result[:orphaned_keys], @result[:foreign_owned_keys]]
#=> [[], [], [], []]

## repair_multi_indexes! has nothing to rebuild and leaves both buckets as they were
repair = NestedScopeClub.repair_multi_indexes!
[repair, @client.smembers(@nested_key), @client.smembers("nested_scope_fed:inv\xFF:division_index:rôle".b)]
#=> [{rebuilt: [], rebuilt_per_scope: [], skipped: []}, ['club-1'], ['club-0']]

## other_record_key gives the longer scope's identifier BINARY and the bucket name UTF-8
ownership = Familia::Features::Relationships::Indexing::RecordKeyOwnership
other_id, name = ownership.other_record_key(@nested_key, NestedScopeFederation, "inv\xFF".b)
[other_id == "inv\xFF:division_index:z".b, other_id.encoding, name, name.encoding]
#=> [true, Encoding::BINARY, 'division_index:rôle', Encoding::UTF_8]

@cleanup.call
