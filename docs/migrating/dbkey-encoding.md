# Migrating dbkey encodings

PR #453 changes the Ruby encoding that `Familia.join` gives a key, and with
it the encoding of `Familia.dbkey`, `Horreum.dbkey`, `Horreum#dbkey` and the
`dbkey` of a DataType that has a parent. The bytes of every key are
unchanged, so no stored key moves. One stored value changes: the
participations reverse-index entry for a target whose identifier is in an
encoding other than UTF-8 or BINARY. Sections that do not apply to your
application need no action.

Check your code if it does any of the following:

- reads `dbkey.encoding`, or compares, hashes or deduplicates dbkeys that come
  from different places, such as a key it built and a key from `SCAN`
- parses the command text `DatabaseLogger` captures or writes to unstructured
  log lines
- rescues `Encoding::CompatibilityError` around `Familia.join`, a `dbkey`,
  `exists?`, `load`, `save`, `destroy!`, the `add_to_*` index and
  participation methods, or the audits
- uses `participates_in` with identifiers in an encoding such as ISO-8859-1

## A key is UTF-8 when its bytes are valid UTF-8, BINARY otherwise

redis-client labels every key and member it reads this way. Its Ruby
driver's `parse_blob` (`resp3.rb`, redis-client 0.29.0) runs
`str.force_encoding(Encoding::BINARY) unless str.valid_encoding?`.
`Familia.join` now applies the same rule to the key it returns, through the
new `Familia.normalize_key_encoding(str)`, so a key built from an identifier
is `==` to the same key read back from the server.

| Identifier given as | Key before | Key after |
|---|---|---|
| ASCII `String`, `Symbol`, `Integer` | UTF-8 | UTF-8 |
| UTF-8, valid | UTF-8 | UTF-8 |
| UTF-8 with invalid bytes, e.g. `"bad\xFF"` | UTF-8 | BINARY |
| BINARY whose bytes are valid UTF-8, e.g. `'zoé'.b` | BINARY | UTF-8 |
| BINARY with invalid bytes, e.g. `"bin\xFE".b` | BINARY | BINARY |
| ISO-8859-1 with non-ASCII bytes, e.g. `"caf\xE9"` | ISO-8859-1 | BINARY, or UTF-8 when the bytes are valid UTF-8 |

That is with an ASCII class prefix. With a non-ASCII prefix such as
`prefix 'équipe'`, the last three rows raised `Encoding::CompatibilityError`
and now return the key. `Familia.join` of parts that are all US-ASCII or
Symbols returns UTF-8 instead of US-ASCII. That label change is not visible
to `==` or Hash lookups, because the result is ASCII-only.

These keep the encoding they are given and are not normalized: a DataType's
`dbkey:` option, a standalone DataType's key, and the patterns
`dbkey_pattern`, `scan_pattern` and `find_keys` build. `dbkey_pattern` still
raises `Encoding::CompatibilityError` for a BINARY or ISO-8859-1 identifier
glob with non-ASCII bytes under a non-ASCII prefix.

**What to do.** Compare keys with `==` or use them as Hash keys; do not
branch on `dbkey.encoding`. To compare a key from another source with one
Familia built, pass it through `Familia.normalize_key_encoding` first. Code
that rescued `Encoding::CompatibilityError` to skip such records can drop the
rescue.

## DatabaseLogger command text

`DatabaseLogger.command_string` gives the text of captured commands
(`DatabaseLogger.capture_commands`) and of unstructured log lines. It now
always returns UTF-8 or ASCII-only text. When the joined command is not valid
UTF-8, or its arguments' encodings cannot be joined, each argument's bytes
are read as UTF-8 and each byte that is not valid UTF-8 is written as `\xNN`:

```ruby
# ZADD with a UTF-8 key and a BINARY member "bad\xFF"
# Before: Encoding::CompatibilityError, after the command had run
# After:  "ZADD équipe:instances 1 bad\\xFF"   (a literal backslash)

# SET with a BINARY key whose bytes are valid UTF-8, 'zoé'.b
# Before: "SET zo\xC3\xA9 v" (BINARY)
# After:  "SET zoé v"        (UTF-8)
```

Structured log lines (`args=`) are unchanged.

**What to do.** A parser that read raw bytes from captured commands should
read `\xNN` escapes instead. An argument that holds a literal backslash
followed by `xNN` renders the same way, so do not decode the text back to
bytes.

## Participations reverse index for ISO-8859-1 identifiers

A participant records each collection it joins in its `participations` set,
as the JSON-encoded collection key. For a target whose identifier is in an
encoding such as ISO-8859-1 and has non-ASCII bytes, JSON encoding transcoded
the key to UTF-8, so 2.13 and 2.14 stored `"federation:caf\xC3\xA9:clubs"` for
the collection at `federation:caf\xE9:clubs`. The entry now holds the
collection key's bytes, `"federation:caf\xE9:clubs"`. Entries for
identifiers in UTF-8 or BINARY are unchanged.

After the upgrade, `remove_from_*` does not remove an entry written by 2.13 or
2.14, and adding the membership again leaves both entries. A process still on
2.14 does not remove an entry written by this version either. The collection
membership itself is removed either way.

`participating_ids_for_target`, `participating_in_target?` and
`current_participations` now raise `ArgumentError` for such a target, as they
already did for a target whose identifier is not valid UTF-8. With 2.14,
`participating_ids_for_target` returned an identifier that found no record
and `current_participations` left the membership out.

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
