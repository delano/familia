# try/bug_fixes/invalid_scope_id_non_ascii_value_audit_try.rb
#
# frozen_string_literal: true

# An instance-scoped multi_index bucket key is
# "{scope_prefix}:{scope_id}:{index_name}:{field_value}". When the scope
# identifier is not valid UTF-8, redis-client returns the whole key as
# BINARY. parse_instance_scoped_bucket_key split the key as bytes and gave
# both parts the key's encoding, so a non-ASCII field value such as 'rôle'
# came back BINARY while the indexed field reads it as UTF-8. The two were
# not ==, so audit_multi_indexes reported the bucket's member as a stale
# :value_mismatch and the bucket as a :field_value_unheld orphan, and
# repair_multi_indexes! rebuilt the scope on every run without reaching
# :ok. Each part now gets the encoding Familia.normalize_key_encoding gives
# its own bytes: the scope id stays BINARY, the field value is UTF-8.

require_relative '../support/helpers/test_helpers'

class ::UnheldValueFederation < Familia::Horreum
  feature :relationships

  prefix 'ligue_fédérale'
  identifier_field :fid
  field :fid
end

class ::UnheldValueClub < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid
  field :division

  multi_index :division, :division_index, within: UnheldValueFederation
  participates_in UnheldValueFederation, :clubs
end

@cleanup = lambda do
  [UnheldValueFederation, UnheldValueClub].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

@federation = UnheldValueFederation.new(fid: "inv\xFF")
@federation.save
@club = UnheldValueClub.new(cid: 'club-1', division: 'rôle')
@club.save
@club.add_to_unheld_value_federation_clubs(@federation)
@club.add_to_unheld_value_federation_division_index(@federation)
@bucket_pattern = 'ligue_fédérale:*:division_index:*'
@bucket_key = UnheldValueFederation.dbclient.scan_each(match: @bucket_pattern).first

## the bucket key holds the invalid scope id and the UTF-8 value, and comes back BINARY
[@bucket_key == "ligue_fédérale:inv\xFF:division_index:rôle".b, @bucket_key.encoding]
#=> [true, Encoding::BINARY]

## the audit of the index is :ok
@result = UnheldValueClub.audit_multi_indexes.first
[@result[:index_name], @result[:status], @result.fetch(:missing_status, :ok)]
#=> [:division_index, :ok, :ok]

## nothing is reported stale, missing or orphaned
[@result[:stale_members], @result[:missing], @result[:orphaned_keys]]
#=> [[], [], []]

## repair_multi_indexes! has nothing to rebuild
UnheldValueClub.repair_multi_indexes!
#=> {rebuilt: [], rebuilt_per_scope: [], skipped: []}

## the bucket and its member are left as they were
UnheldValueFederation.dbclient.smembers(@bucket_key)
#=> ['club-1']

## a second audit is still :ok
UnheldValueClub.audit_multi_indexes.first[:status]
#=> :ok

## with the bucket deleted, the audit reports the club missing with the UTF-8 value
UnheldValueFederation.dbclient.del(@bucket_key)
missing = UnheldValueClub.audit_multi_indexes.first[:missing]
missing.map { |entry| [entry[:identifier], entry[:scope_id] == "inv\xFF".b, entry[:field_value]] }
#=> [['club-1', true, 'rôle']]

## repair_multi_indexes! restores the bucket and the audit is :ok again
UnheldValueClub.repair_multi_indexes!
[UnheldValueFederation.dbclient.smembers(@bucket_key), UnheldValueClub.audit_multi_indexes.first[:status]]
#=> [['club-1'], :ok]

@cleanup.call
