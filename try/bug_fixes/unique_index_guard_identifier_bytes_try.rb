# try/bug_fixes/unique_index_guard_identifier_bytes_try.rb
#
# frozen_string_literal: true

# The unique index guards (guard_unique_<index>! and
# guard_unique_<scope>_<index>!) compared the identifier stored in the
# index with the record's identifier as Strings. The stored identifier
# comes back BINARY when its bytes are not valid UTF-8, while a loaded
# record's identifier is JSON-decoded as UTF-8 with the same bytes, so the
# two were not == and re-saving a loaded record whose identifier is not
# valid UTF-8 raised Familia::RecordExistsError against its own entry. The
# guards now compare the identifiers' bytes.
#
# An index hashkey the application declares itself, before unique_index,
# is not a reference hash: it returns a stored Integer identifier as an
# Integer, and comparing its bytes raised NoMethodError instead of
# Familia::RecordExistsError. The guards compare the string forms.

require_relative '../support/helpers/test_helpers'

class ::GuardBytesOrg < Familia::Horreum
  feature :relationships

  prefix 'guard_bytes_org'
  identifier_field :oid
  field :oid
end

class ::GuardBytesMember < Familia::Horreum
  feature :relationships

  prefix 'guard_bytes_member'
  identifier_field :uid
  field :uid
  field :email
  field :badge
  field :role

  unique_index :email, :email_lookup
  unique_index :badge, :badge_index, within: GuardBytesOrg
end

class ::GuardAppOrg < Familia::Horreum
  feature :relationships

  prefix 'guard_app_org'
  identifier_field :oid
  field :oid
  hashkey :badge_index
end

class ::GuardAppMember < Familia::Horreum
  feature :relationships

  prefix 'guard_app_member'
  identifier_field :uid
  field :uid
  field :email
  field :badge
  class_hashkey :email_lookup

  unique_index :email, :email_lookup
  unique_index :badge, :badge_index, within: GuardAppOrg
end

@cleanup = lambda do
  [GuardBytesOrg, GuardBytesMember, GuardAppOrg, GuardAppMember].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

@org = GuardBytesOrg.new(oid: 'org-1')
@org.save
GuardBytesMember.new(uid: "bad\xFF", email: 'bad@example.com', role: 'r1').save
GuardBytesMember.new(uid: "bin\xFE".b, email: 'bin@example.com', role: 'r1').save

## the class-level index returns the stored identifier as BINARY
GuardBytesMember.email_lookup.get('bad@example.com').encoding
#=> Encoding::BINARY

## a loaded record whose identifier is UTF-8 with an invalid byte saves again
loaded = GuardBytesMember.find_by_id("bad\xFF")
loaded.role = 'r2'
[loaded.identifier.encoding, loaded.save, GuardBytesMember.find_by_id("bad\xFF").role]
#=> [Encoding::UTF_8, true, 'r2']

## a loaded record saved with a BINARY identifier saves again
loaded = GuardBytesMember.find_by_id("bin\xFE".b)
loaded.role = 'r2'
[loaded.save, GuardBytesMember.find_by_id("bin\xFE".b).role]
#=> [true, 'r2']

## another record still cannot take the email
GuardBytesMember.new(uid: 'other', email: 'bad@example.com').save
#=!> Familia::RecordExistsError

## the instance-scoped guard accepts the loaded record's own entry
member = GuardBytesMember.new(uid: "scoped\xFF", badge: 'b1')
member.save
member.add_to_guard_bytes_org_badge_index(@org)
loaded = GuardBytesMember.find_by_id("scoped\xFF")
[loaded.badge, loaded.guard_unique_guard_bytes_org_badge_index!(@org)]
#=> ['b1', nil]

## and refuses another record with that badge
GuardBytesMember.new(uid: 'other', badge: 'b1').guard_unique_guard_bytes_org_badge_index!(@org)
#=!> Familia::RecordExistsError

## an index the application declared returns a stored Integer identifier as an Integer
GuardAppMember.new(uid: 5, email: 'app@example.com', badge: 'b5').save
[GuardAppMember.email_lookup.opts[:reference], GuardAppMember.email_lookup.get('app@example.com')]
#=> [nil, 5]

## a loaded record with an Integer identifier saves again
GuardAppMember.find_by_id(5).save
#=> true

## another record cannot take the email
GuardAppMember.new(uid: 6, email: 'app@example.com').save
#=!> Familia::RecordExistsError

## the instance-scoped guard accepts the record's own entry in such an index
@app_org = GuardAppOrg.new(oid: 'org-app')
@app_org.save
GuardAppMember.find_by_id(5).add_to_guard_app_org_badge_index(@app_org)
GuardAppMember.find_by_id(5).guard_unique_guard_app_org_badge_index!(@app_org)
#=> nil

## and refuses another record with that badge
GuardAppMember.new(uid: 6, badge: 'b5').guard_unique_guard_app_org_badge_index!(@app_org)
#=!> Familia::RecordExistsError

@cleanup.call
