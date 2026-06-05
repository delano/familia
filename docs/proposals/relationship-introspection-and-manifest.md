# Proposal: A Persisted Familia Manifest (future work)

> **Status:** The project-wide introspection and the stale-index boot guard
> described in earlier drafts of this proposal are now **implemented** — see
> [Relationships → Introspection](../guides/feature-relationships.md#introspection).
> What remains open, and the only thing this document now proposes, is the
> *optional persisted manifest* below.

## Background

The v2.10.0 unique-index storage change (JSON-encoded → raw identifiers, see
[migrating/v2.10.0](../migrating/v2.10.0.md#unique-index-storage-format)) is
read-compatible going forward, but indexes written under 2.9.x still hold quoted
values like `"\"dom_abc123\""`. A reported production incident: a `find_by_*`
lookup over a 2.9-era `unique_index` silently returned nothing and **fell back to
a default**, with no migration, guard, or alert.

### What shipped (closes the incident)

Built on the `each_record` reference-collection pattern so callers never touch
Familia internals:

- **`Familia::IndexDescriptor`** — pairs an owning class with one of its
  `IndexingRelationship`s, exposing `coordinate`, `each_record`, `rebuild!`,
  and `stale_format?`.
- **Project-wide aggregators** — `Familia.index_descriptors`, `unique_indexes`,
  `multi_indexes`, `participation_descriptors` (all filter by `cardinality`,
  `class_level:`, and `owner:`).
- **The boot guard** — `Familia.stale_indexes` + `Familia.assert_indexes_current!`,
  reusing the read path's `Familia.legacy_json_encoded?` predicate so detection
  and stripping never disagree. This is the piece that surfaces an un-rebuilt
  index before it degrades a lookup.

Implementation: `lib/familia/index_descriptor.rb`,
`try/features/relationships/index_introspection_try.rb`.

These already give a downstream app its migration helper
(`Familia.stale_indexes.each(&:rebuild!)`), boot assertion, and CI smoke test —
**without** persisting anything.

## The remaining idea: an opt-in persisted manifest

The original ask also floated an "idempotent representation of the entire familia
clan persisted to Redis for auditing/recovery." This is genuinely separable from
the incident fix and worth doing only if a concrete auditing/recovery use case
drives its exact shape. Sketch:

### Config + API

```ruby
Familia.configure do |config|
  config.persist_manifest = true            # opt-in; default false
  config.manifest_key      = 'myapp:manifest'
end

Familia.persist_manifest!(force: false)  # write iff fingerprint changed
Familia.manifest                          # read the persisted snapshot back
Familia.manifest_drift?                   # persisted topology != current?
```

Follow the `lib/familia/settings.rb` accessor pattern for the config option.
**Do not** write from `Horreum.inherited` — the clan is half-loaded there; trigger
the write explicitly after boot (an initializer / deploy task), with an optional
`at_exit` safety net gated by the flag.

### Redis structures (written together in one `MULTI/EXEC`)

| Key | Type | Contents |
|-----|------|----------|
| `…:manifest` | HashKey | field = `"User"`, value = JSON class descriptor (fields, identifier_field, indexes, participations, prefix, logical_database) |
| `…:manifest:indexes` | HashKey | field = `"User:email_lookup"`, value = JSON (field, cardinality, within, dbkey) — denormalized for "enumerate all indexes" |
| `…:manifest:meta` | StringKey (JSON) | `{ familia_version, fingerprint, generated_at }` |

### Idempotency & advanced Redis features

- **Fingerprint short-circuit** — `SHA256` of canonical (sorted) JSON gates the
  write; unchanged topology is a no-op (cheap, idempotent across N booting
  processes).
- **Atomic `DEL`+repopulate inside `MULTI/EXEC`** — readers see the old or the
  new manifest, never a mix; classes removed from the codebase are pruned.
- **Serialize from `Familia.index_descriptors`** (already implemented), so the
  persisted `:indexes` hash and the live aggregators describe the same
  coordinates; `manifest_drift?` is just a fingerprint compare.
- Write via `Familia.dbclient` directly (not as a `Horreum`) so the manifest does
  not appear in the clan it describes. Namespace under `Familia.prefix`; no TTL.

### Honest caveats (why this is *future* work)

- It does **not** solve the acute incident — the boot guard already does, by
  reading live index data. The manifest's value is cross-process / cross-deploy
  topology comparison and provenance, a narrower benefit.
- `manifest_drift?` as sketched detects *topology* drift (which indexes exist),
  not the *data-format* drift that caused the incident. "Recovery" would need a
  design beyond a snapshot.
- It is the highest-complexity, lowest-urgency piece; defer until a concrete use
  case pins down the exact contents and the recovery path.

## Open questions

- Write trigger: explicit only, `at_exit` safety net, or lazy-on-first-read?
- Snapshot scope: indexes + participations + fields is the core; also
  `related_fields`, feature options, encryption key versions?
- Is topology-in-Redis the right place at all, given topology is derivable from
  code at boot?

## See Also

- [Relationships → Introspection](../guides/feature-relationships.md#introspection) — the implemented API
- `lib/familia/index_descriptor.rb` — descriptors, aggregators, boot guard
- `lib/familia/data_type/collection_base.rb` — `each_record` (the design pattern)
- `lib/familia/horreum/management/` — the audit/repair layer this complements
