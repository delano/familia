# Migrating dbkey encodings

Compared with 2.13.0, PR #453 changes the Ruby encoding that `Familia.join`
gives a key, and with it the encoding of `Familia.dbkey`, `Horreum.dbkey`,
`Horreum#dbkey` and the `dbkey` of a DataType that has a parent. The bytes
of every key are unchanged, so no stored key moves. One stored value
changes: the participations reverse-index entry for a target whose
identifier is in an encoding other than UTF-8 or BINARY. This version also
writes some records that 2.13.0 refused to write; see
[Rolling back to 2.13.0](#rolling-back-to-2130).
Sections that do not apply to your application need no action.

Check your code if it does any of the following:

- reads `dbkey.encoding`, or compares, hashes or deduplicates dbkeys that come
  from different places, such as a key it built and a key from `SCAN`
- parses the command text `DatabaseLogger` captures or writes to unstructured
  log lines, or parses Familia's own log lines
- rescues `Encoding::CompatibilityError` around `Familia.join`, a `dbkey`,
  `exists?`, `load`, `save`, `destroy!`, the `add_to_*` index and
  participation methods, or the audits
- uses `participates_in` with identifiers in an encoding such as ISO-8859-1
- may need to roll back to 2.13.0 after this version has written data

## A key is UTF-8 when its bytes are valid UTF-8, BINARY otherwise

redis-client's default Ruby driver labels every key and member it reads
this way: its `parse_blob` (`resp3.rb`, redis-client 0.29.0) runs
`str.force_encoding(Encoding::BINARY) unless str.valid_encoding?`.
`Familia.join` now applies the same rule to the key it returns, through the
new `Familia.normalize_key_encoding(str)`, so a key built from an identifier
is `==` to the same key read back from the server.

| Identifier given as | Key in 2.13.0 | Key in this version |
|---|---|---|
| ASCII `String`, `Symbol`, `Integer` | UTF-8, or US-ASCII under a Symbol prefix such as the default (see below) | UTF-8 |
| UTF-8, valid | UTF-8 | UTF-8 |
| UTF-8 with invalid bytes, e.g. `"bad\xFF"` | UTF-8 | BINARY |
| BINARY whose bytes are valid UTF-8, e.g. `'zoé'.b` | BINARY | UTF-8 |
| BINARY with invalid bytes, e.g. `"bin\xFE".b` | BINARY | BINARY |
| ISO-8859-1 with non-ASCII bytes, e.g. `"caf\xE9"` | ISO-8859-1 | BINARY, or UTF-8 when the bytes are valid UTF-8 |

That is with an ASCII class prefix. With a non-ASCII prefix such as
`prefix 'équipe'`, the last three rows raised `Encoding::CompatibilityError`
and now return the key. In 2.13.0 a key whose bytes are all ASCII took the
encoding of its first part: US-ASCII when that is a Symbol or Integer, such
as a class's default prefix, and BINARY or ISO-8859-1 when it is a String in
that encoding. It is now UTF-8. That label change is not visible to `==` or
Hash lookups, because the key is ASCII-only.

These keep the encoding they are given and are not normalized: a DataType's
`dbkey:` option, a standalone DataType's key, and the patterns
`dbkey_pattern`, `scan_pattern` and `find_keys` build. `dbkey_pattern`, which
2.13.0 does not have, raises `Encoding::CompatibilityError` for a BINARY or
ISO-8859-1 identifier glob with non-ASCII bytes under a non-ASCII prefix.

**What to do.** Compare keys with `==` or use them as Hash keys; do not
branch on `dbkey.encoding`. To compare a key from another source with one
Familia built, pass it through `Familia.normalize_key_encoding` first. Code
that rescued `Encoding::CompatibilityError` from `Familia.join` or a `dbkey`
to skip such records can drop the rescue; `dbkey_pattern` raises it as
described above.

## Command and log text

`DatabaseLogger.command_string` gives the text of captured commands
(`DatabaseLogger.capture_commands`) and of unstructured log lines. It now
always returns UTF-8 or ASCII-only text. When the joined command is not valid
UTF-8, or its arguments' encodings cannot be joined, each argument's bytes
are read as UTF-8 and each byte that is not valid UTF-8 is written as `\xNN`:

```ruby
# ZADD with a UTF-8 key and a BINARY member "bad\xFF"
# 2.13.0:       Encoding::CompatibilityError, after the command had run
# This version: "ZADD équipe:instances 1 bad\\xFF"   (a literal backslash)

# SET with a BINARY key whose bytes are valid UTF-8, 'zoé'.b
# 2.13.0:       "SET zo\xC3\xA9 v" (BINARY)
# This version: "SET zoé v"        (UTF-8)
```

Structured log lines (`args=`) are unchanged.

Familia's own log lines follow the same rule where they name a key next to
other text: the deserialization, `find_by_id`, `commit_fields`, `refresh!`,
`update_expiration`, `serialize_value` and `HashKey` write lines, the
warning for an indexed field value longer than 256 characters, the
`key=value` context of `Familia.debug`, `Familia.info` and `Familia.error`,
and `Familia.trace` output. So do the messages of the `TypeError` a
`HashKey` store raises, of `WatchAbortError` and of the dirty-write warning
and error, and of `Familia::IdentifierMismatchError`, which 2.13.0 does not
have. A key whose
bytes are not valid UTF-8 now reads `team:bin\xFE:members` there, with a
literal backslash. Other log lines that name a key, such as those of the
atomic index rebuild and of `repair_participations!`, write its bytes as
they are. The legacy JSON-encoded identifier warning writes `->` where it
wrote `→`.

**What to do.** A parser that read raw bytes from captured commands or log
lines should read `\xNN` escapes instead. An argument that holds a literal
backslash followed by `xNN` renders the same way, so do not decode the text
back to bytes.

## Participations reverse index for ISO-8859-1 identifiers

A participant records each collection it joins in its `participations` set,
as the JSON-encoded collection key. For a target whose identifier is in an
encoding such as ISO-8859-1 and has non-ASCII bytes, JSON encoding transcoded
the key to UTF-8, so 2.13.0 stored `"federation:caf\xC3\xA9:clubs"` for
the collection at `federation:caf\xE9:clubs`. The entry now holds the
collection key's bytes, `"federation:caf\xE9:clubs"`. Entries for
identifiers in UTF-8 or BINARY are unchanged.

After the upgrade, `remove_from_<target>_<collection>` does not remove an
entry written by 2.13.0, and adding the membership again leaves both
entries: `participating_ids_for_target`, `<target>_ids` and `<target>_count`
then list the target twice, as `"café"` and `"caf\xE9".b`, until the old
entry is removed (see **What to do** below). A process still on 2.13.0 does
not remove an entry written by this version either. The collection
membership itself is removed either way.

The participation readers parse an entry by its bytes.
`participating_ids_for_target` returns the identifier's bytes: as the BINARY
identifier `"caf\xE9".b` when they are not valid UTF-8, as for `"caf\xE9"`,
and as the UTF-8 identifier `"été"` when they are, as for
`"\xC3\xA9t\xC3\xA9"` labelled ISO-8859-1. Either finds the target. With
2.13.0 it returned the bytes transcoded to UTF-8, `"café"` and `"Ã©tÃ©"`,
which found no record. `participating_in_target?` matches the entry with or
without collection names.

`current_participations`, and so `relationship_status`, leave the membership
out and return the participant's other memberships, as they did with 2.13.0.
The target loads with its identifier transcoded (see below), and that
identifier's collection is not the one the participant joined.

**What to do.** Prefer UTF-8 identifiers. A field value is stored as JSON,
which transcodes it, so a record saved under `"caf\xE9"` (ISO-8859-1) loads
with the UTF-8 identifier `"café"`, whose key is not the one it was saved
under. To clear a legacy entry, remove the transcoded collection key, built
from the identifier as your application holds it:

```ruby
fed = Federation.new(fid: latin1_id)
legacy = fed.clubs.dbkey.b.force_encoding(latin1_id.encoding).encode(Encoding::UTF_8)
club.participations.remove(legacy)
```

## Instance-scoped indexes under ISO-8859-1 scope identifiers

The same transcoding affects `audit_multi_indexes` and
`repair_multi_indexes!` for an instance-scoped `multi_index` whose scope
identifier is in an encoding such as ISO-8859-1 and has non-ASCII bytes. The
audit loads the scope with its transcoded identifier and reads a
participation collection other than the one the records joined, so it
reports each of the scope's buckets as an orphaned key with reason
`:field_value_unheld`. `repair_multi_indexes!` rebuilds the scope on every
run, leaves the keys as they were, and the next audit reports the same. 2.13.0
does the same with an ASCII field value and raised
`Encoding::CompatibilityError` when writing a non-ASCII one, which this
version writes. The index itself is correct: `find_all_by_<field>` on a
scope built from the original identifier returns the records. On the scope
`find_by_id` loads, whose identifier is transcoded, it returns none.

**What to do.** Prefer UTF-8 identifiers for scope classes. Until such a
scope is migrated to a UTF-8 identifier, treat these audit results for it as
expected and do not schedule `repair_multi_indexes!` on them.

## Rolling back to 2.13.0

Under the rule above, this version writes records that 2.13.0 raised
`Encoding::CompatibilityError` for before writing anything, and
participations entries that differ from the ones 2.13.0 wrote. 2.13.0 can
read some of them and not others:

- **Instance-scoped indexes under a scope identifier that is not valid
  UTF-8**, given as BINARY (`"bin\xFE".b`) or ISO-8859-1 (`"caf\xE9"`), with a
  non-ASCII field value such as `'rôle'`, or with any field value when the
  scope class prefix holds non-ASCII characters. 2.13.0 loads such a
  record, but its `save` raises, and its `destroy!` raises before deleting
  anything, so the record's hash, its `_idx_scopes` key, any
  `participations` key, and its bucket membership stay.
  `audit_multi_indexes`, `health_check` and `repair_all!` of the record's
  class raise when the scope class prefix holds non-ASCII characters, or
  for a BINARY scope identifier when the record's class declares
  `participates_in` of the scope class. Otherwise they do not:
  `audit_multi_indexes` reports the record as a stale member with reason
  `:value_mismatch`, and, for an ISO-8859-1 scope identifier with
  `participates_in`, the scope's buckets as `:field_value_unheld` orphans;
  `health_check` reports the class unhealthy, and `repair_all!` returns
  `:ok` and changes nothing.
- **Records under a non-ASCII class prefix** (`prefix 'membré'`) whose
  identifier bytes are not valid UTF-8, given as BINARY or ISO-8859-1. 2.13.0
  raises in `load` and `exists?`, in `find_by_id` and class `destroy!` given
  the identifier read back from `instances`, and in `health_check` and
  `repair_all!` of the class. For an identifier whose bytes are valid UTF-8,
  given as BINARY (`'zoé'.b`) or ISO-8859-1, 2.13.0 raises in `load` and
  `exists?` given it as the application holds it; given the UTF-8
  identifier read back from `instances`, `find_by_id` and class
  `destroy!` work.
- **Records whose indexed field value is not valid UTF-8**, given as BINARY
  (`"r\xFEle".b`), under a non-ASCII class prefix. 2.13.0 loads such a record,
  but `health_check` and `repair_all!` of its class raise, and so does
  `audit_multi_indexes` or `audit_unique_indexes` for the kind of index on
  the field. With a `multi_index` on the field, its `save` raises, and its
  `destroy!` raises and leaves the hash. 2.13.0 fails the same way for such a
  value under an ASCII prefix, and for one with only a `unique_index` on the
  field under a non-ASCII prefix, both of which it could write.
- **Participations reverse-index entries** for ISO-8859-1 targets, as
  described above: 2.13.0 does not remove an entry this version wrote. When
  the target identifier's bytes are not valid UTF-8, as for `"caf\xE9"`,
  2.13.0's `current_participations`, `relationship_status`,
  `participating_ids_for_target` and the generated `<target>_ids`,
  `<target>_instances` and `<target>_count` of a participant holding such
  an entry raise `ArgumentError`, and so does `participating_in_target?`
  given collection names when it reads that entry before a matching one,
  so 2.13.0 no longer lists that participant's other memberships
  either. Remove such a membership with this version
  (`remove_from_<target>_<collection>`) before rolling back.

2.13.0 changes nothing for these records when it raises. Running this
version again makes them readable, savable and deletable again.

**What to do.** Before rolling back, delete or migrate the records above, or
plan to run this version again to remove them. Delete a record whose own
identifier is ISO-8859-1 with the class-level `destroy!(id)`, given the
identifier as your application holds it or as read from `instances`, not
through a loaded instance: the record loads with the transcoded UTF-8
identifier (`"café"` for `"caf\xE9"`, as described above), so the loaded
instance's `destroy!` targets another key and leaves the record. Do not
rely on `health_check` or `repair_all!` on 2.13.0 to find these records:
they raise for some of them, report others as stale members or orphaned
index buckets that `repair_all!` leaves as they are, and report the class of
a participant holding a participations entry described above as healthy.
