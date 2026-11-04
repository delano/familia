# try/bug_fixes/participation_entry_invalid_utf8_try.rb
#
# frozen_string_literal: true

# A participant's participations set holds the key of each collection it
# joined, "targetprefix:targetid:collection". For a target whose
# identifier bytes are not valid UTF-8, such as ISO-8859-1 "caf\xE9" or
# BINARY "bin\xFE", the entry holds those bytes and is read back as a
# UTF-8 String with invalid bytes, which String#split rejects with
# ArgumentError (invalid byte sequence in UTF-8):
#
# - current_participations split each entry outside its per-entry rescue,
#   so it, and relationship_status, raised for any participant holding such
#   an entry and returned none of its other memberships;
# - participating_ids_for_target raised for the target class, and
#   participating_in_target? given collection names raised when it reached
#   the entry before a match.
#
# The readers now split an entry by its bytes, each part in the encoding
# Familia.normalize_key_encoding gives it.

require_relative '../support/helpers/test_helpers'

class ::EntryBytesFederation < Familia::Horreum
  feature :relationships

  identifier_field :fid
  field :fid
end

class ::EntryBytesClub < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid

  participates_in EntryBytesFederation, :clubs
end

delete_test_dbkeys(EntryBytesFederation, EntryBytesClub)

@latin1_id = "caf\xE9".dup.force_encoding(Encoding::ISO_8859_1)
@plain = EntryBytesFederation.new(fid: 'plain')
@plain.save
@latin1 = EntryBytesFederation.new(fid: @latin1_id)
@latin1.save
@club = EntryBytesClub.new(cid: 'club-1')
@club.save
@club.add_to_entry_bytes_federation_clubs(@plain)
@club.add_to_entry_bytes_federation_clubs(@latin1)
@loaded = EntryBytesClub.find_by_id('club-1')

## the entry for the ISO-8859-1 target holds the collection key's bytes, which are not valid UTF-8
@loaded.participations.members.map(&:b).sort
#=> ["entry_bytes_federation:caf\xE9:clubs".b, 'entry_bytes_federation:plain:clubs'.b]

## current_participations returns the participant's other memberships
# The target loads with the transcoded identifier "café", whose clubs
# collection is not the one the club joined, so that membership is left out.
@loaded.current_participations.map(&:target_id)
#=> ['plain']

## relationship_status lists them too
@loaded.relationship_status[:current_participations].map(&:target_id)
#=> ['plain']

## participating_ids_for_target returns the target identifier's bytes as BINARY
@loaded.participating_ids_for_target(EntryBytesFederation).sort_by(&:b)
#=> ["caf\xE9".b, 'plain']

## the identifier it returns names the ISO-8859-1 target's key
@latin1_entry_id = @loaded.participating_ids_for_target(EntryBytesFederation).reject(&:ascii_only?).first
[@latin1_entry_id.encoding, EntryBytesFederation.exists?(@latin1_entry_id), @loaded.entry_bytes_federation_instances.size]
#=> [Encoding::BINARY, true, 2]

## participating_in_target? given collection names reads the entry
[@loaded.participating_in_target?(EntryBytesFederation, ['clubs']),
 @loaded.participating_in_target?(EntryBytesFederation, ['other'])]
#=> [true, false]

## participating_ids_for_target given another collection name returns none
@loaded.participating_ids_for_target(EntryBytesFederation, ['other'])
#=> []

## a membership in a BINARY target identifier that is not valid UTF-8 is reported
@binary = EntryBytesFederation.new(fid: "bin\xFE".b)
@binary.save
@club.add_to_entry_bytes_federation_clubs(@binary)
@memberships = EntryBytesClub.find_by_id('club-1').current_participations
@memberships.map(&:target_id).sort_by(&:b)
#=> ["bin\xFE".b, 'plain']

## its membership names the collection and loads the target
@binary_membership = @memberships.find { |membership| !membership.target_id.ascii_only? }
[@binary_membership.target_id.encoding, @binary_membership.collection_name, @binary_membership.type,
 @binary_membership.score.is_a?(Float), @binary_membership.target_instance&.dbkey == @binary.dbkey]
#=> [Encoding::BINARY, :clubs, :sorted_set, true, true]

## a membership in a UTF-8 target identifier with invalid bytes is reported as well
@utf8 = EntryBytesFederation.new(fid: "u8\xFE")
@utf8.save
@club.add_to_entry_bytes_federation_clubs(@utf8)
EntryBytesClub.find_by_id('club-1').current_participations.map(&:target_id).sort_by(&:b)
#=> ["bin\xFE".b, 'plain', "u8\xFE".b]

## an entry transcoded to UTF-8, as 2.14 wrote it for the ISO-8859-1 target, is read without raising
@legacy_entry = @latin1.clubs.dbkey.b.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
@club.participations.add(@legacy_entry)
@reloaded = EntryBytesClub.find_by_id('club-1')
[@reloaded.current_participations.map(&:target_id).sort_by(&:b),
 @reloaded.participating_ids_for_target(EntryBytesFederation).sort_by(&:b)]
#=> [["bin\xFE".b, 'plain', "u8\xFE".b], ["bin\xFE".b, 'café', "caf\xE9".b, 'plain', "u8\xFE".b]]

## the transcoded identifier finds no record
EntryBytesFederation.exists?('café')
#=> false

delete_test_dbkeys(EntryBytesFederation, EntryBytesClub)
