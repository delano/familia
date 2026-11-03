# try/bug_fixes/invalid_utf8_field_value_index_try.rb
#
# frozen_string_literal: true

# A field value given as BINARY with bytes that are not valid UTF-8, such
# as "r\xFEle".b, is saved as is and loads back as UTF-8 with the same
# bytes. The indexes then failed on the loaded record:
#
# - The blank checks called String#strip, which raises
#   Encoding::CompatibilityError on such a String: save and destroy! of the
#   record, the audits and so health_check and repair_all! raised.
# - validate_field_value matched its patterns against the String, which
#   raises ArgumentError.
# - The audits compared the loaded value with the bucket key or index field
#   the client returned as BINARY, so they reported the record's own entry
#   as stale, missing and orphaned, and repair rebuilt it on every run.
#
# 2.14 raised in Familia.join before writing such a record under a
# non-ASCII prefix, and failed as above under an ASCII prefix. The blank
# checks and patterns now read such a String as bytes, and the audits
# compare the record's value in the encoding the client gives its bytes
# (Familia.normalize_key_encoding).

require_relative '../support/helpers/test_helpers'

class ::InvalidValueOrg < Familia::Horreum
  feature :relationships

  prefix 'org_invalidé'
  identifier_field :oid
  field :oid
end

class ::InvalidValueMember < Familia::Horreum
  feature :relationships

  prefix 'membre_invalidé'
  identifier_field :uid
  field :uid
  field :role
  field :email
  field :division

  multi_index :role, :role_index
  unique_index :email, :email_lookup
  multi_index :division, :division_index, within: InvalidValueOrg
  participates_in InvalidValueOrg, :members
end

@cleanup = lambda do
  [InvalidValueOrg, InvalidValueMember].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

@org = InvalidValueOrg.new(oid: 'org-1')
@org.save
InvalidValueMember.new(uid: 'ok-1', role: 'admin', email: 'ok@example.com', division: 'nord').save

## Familia.blank_text? reads a String that is not valid UTF-8 as bytes
[Familia.blank_text?(" \t\0"), Familia.blank_text?(nil), Familia.blank_text?("r\xFEle"), Familia.blank_text?('rôle')]
#=> [true, true, false, false]

## save writes a record whose indexed values are BINARY and not valid UTF-8
@member = InvalidValueMember.new(uid: 'm-1', role: "r\xFEle".b, email: "e\xFEmail".b, division: "d\xFEv".b)
@member.save
@member.add_to_invalid_value_org_members(@org)
@member.add_to_invalid_value_org_division_index(@org)
InvalidValueMember.find_all_by_role("r\xFEle".b).map(&:uid)
#=> ['m-1']

## the record loads the values as UTF-8 with the same bytes
@loaded = InvalidValueMember.find_by_id('m-1')
[@loaded.role.encoding, @loaded.role.valid_encoding?, @loaded.role.b == "r\xFEle".b]
#=> [Encoding::UTF_8, false, true]

## the multi_index audits are :ok
InvalidValueMember.audit_multi_indexes.map { |result| [result[:index_name], result[:status]] }
#=> [[:role_index, :ok], [:division_index, :ok]]

## the unique index audit finds nothing stale or missing
InvalidValueMember.audit_unique_indexes.map { |result| [result[:stale], result[:missing]] }
#=> [[[], []]]

## health_check is healthy
InvalidValueMember.health_check.healthy?
#=> true

## repair_all! has nothing to fix
InvalidValueMember.repair_all![:status]
#=> :ok

## the loaded record saves again
@loaded.role = "r\xFEle"
@loaded.save
#=> true

## its instance-scoped index entry moves to a new value
@loaded.division = 'sud'
@loaded.save
@loaded.update_in_invalid_value_org_division_index(@org, "d\xFEv")
[@org.find_all_by_division('sud').map(&:uid), @org.division_index_for("d\xFEv").members]
#=> [['m-1'], []]

## destroy! removes the record and its index entries
InvalidValueMember.find_by_id('m-1').destroy!
[InvalidValueMember.exists?('m-1'), InvalidValueMember.find_all_by_role("r\xFEle".b), InvalidValueMember.email_lookup.get("e\xFEmail".b)]
#=> [false, [], nil]

@cleanup.call
