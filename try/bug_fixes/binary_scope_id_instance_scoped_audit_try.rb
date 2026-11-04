# try/bug_fixes/binary_scope_id_instance_scoped_audit_try.rb
#
# frozen_string_literal: true

# An instance-scoped multi_index keeps its buckets under the scope class's
# prefix: "{scope_prefix}:{scope_id}:{index_name}:{field_value}". When the
# scope prefix is non-ASCII (e.g. 'fédération') and a scope identifier is
# not valid UTF-8, redis-client returns the bucket key and the instances
# member as BINARY. audit_multi_indexes raised Encoding::CompatibilityError
# twice: parsing such a bucket key against the UTF-8 scope prefix, and
# rebuilding the expected bucket key from the BINARY scope identifier. Both
# now work on bytes, and the key they produce is == to the stored key.

require_relative '../support/helpers/test_helpers'

class ::BinaryIdFederation < Familia::Horreum
  feature :relationships

  prefix 'fédération'
  identifier_field :fid
  field :fid
  field :name
end

class ::BinaryIdClub < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid
  field :division

  multi_index :division, :division_index, within: BinaryIdFederation
  participates_in BinaryIdFederation, :clubs
end

@cleanup = lambda do
  [BinaryIdFederation, BinaryIdClub].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

@federation = BinaryIdFederation.new(fid: "fed\xFF", name: 'Ligue')
@federation.save
@club = BinaryIdClub.new(cid: 'club-1', division: 'north')
@club.save
@club.add_to_binary_id_federation_clubs(@federation)
@club.add_to_binary_id_federation_division_index(@federation)
@member = BinaryIdFederation.instances.members.first
@bucket_key = BinaryIdFederation.dbclient.scan_each(match: 'fédération:*:division_index:*').first

## the scope identifier comes back from redis-client as BINARY
[@member == "fed\xFF".b, @member.encoding]
#=> [true, Encoding::BINARY]

## the bucket is stored under the scope identifier's bytes and comes back as a BINARY key
[@bucket_key == "fédération:fed\xFF:division_index:north".b, @bucket_key.encoding]
#=> [true, Encoding::BINARY]

## the index factory builds the stored key from the saved scope and from the scope loaded by its member
from_saved = @federation.division_index_for('north').dbkey
from_member = BinaryIdFederation.load(@member).division_index_for('north').dbkey
[from_saved == @bucket_key, from_member == @bucket_key]
#=> [true, true]

## audit_multi_indexes audits the index, including the missing dimension
@result = BinaryIdClub.audit_multi_indexes.first
[@result[:index_name], @result[:status], @result.fetch(:missing_status, :ok)]
#=> [:division_index, :ok, :ok]

## the audit matches the bucket to the scope and the club: nothing stale, missing or orphaned
[@result[:stale_members], @result[:missing], @result[:orphaned_keys]]
#=> [[], [], []]

## with the bucket deleted, the audit reports the club missing under the BINARY scope identifier
BinaryIdFederation.dbclient.del(@bucket_key)
missing = BinaryIdClub.audit_multi_indexes.first[:missing]
missing.map { |entry| [entry[:identifier], entry[:scope_id] == @member, entry[:field_value]] }
#=> [['club-1', true, 'north']]

## with the bucket restored, the audit is clean again
@club.add_to_binary_id_federation_division_index(@federation)
BinaryIdClub.audit_multi_indexes.first[:status]
#=> :ok

@cleanup.call
