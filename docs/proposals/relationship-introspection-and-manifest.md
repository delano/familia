# Proposal: Project-Wide Relationship Introspection & a Persisted Familia Manifest

> **Status:** Proposed (design only — nothing here is implemented yet).
> **Scope:** `Familia.*` module-level helpers, a new `Familia::IndexDescriptor`,
> an opt-in `Familia.configure` option, and a namespaced `Familia.persist_manifest!`.
> **Motivating need:** a way to iterate over *every* `unique_index` in an
> application without the calling code reaching into Familia internals — needed
> for the v2.10.0 unique-index storage migration.

## 1. Motivation

Familia already exposes **per-class** relationship metadata
(`Klass.indexing_relationships`, `Klass.participation_relationships`) and
**per-instance** state (`current_indexings`, `relationship_status`). See
[Introspection](../guides/feature-relationships.md#introspection).

What is missing is a **project-wide** view. Three concrete gaps:

1. **No aggregator.** To answer "what are all the `unique_index`es in this app?"
   today you must sweep `Familia.members` yourself, guard `respond_to?`, filter
   by `cardinality`, and then know the method-naming conventions to actually
   *use* each index. That is exactly the Familia-internals knowledge callers
   should not need.

2. **No durable snapshot.** The clan's topology (which classes exist, their
   fields, indexes, and participations) lives only in loaded Ruby. There is no
   persisted, idempotent representation a deploy/migration/audit can read back
   or diff against.

3. **No way to *detect* stale index data before it breaks at runtime.** When the
   storage format or topology of an index changes, there is no boot-time guard,
   smoke test, or alert — the inconsistency only surfaces as a silent runtime
   regression.

### The incident behind gap #3

The v2.10.0 unique-index storage change (JSON-encoded → raw identifiers, see
[migrating/v2.10.0](../migrating/v2.10.0.md#unique-index-storage-format)) is
read-compatible *going forward*, but indexes written under 2.9.x still hold
quoted values like `"\"dom_abc123\""`. A reported production incident: a
custom-domain lookup (`find_by_*` over a 2.9-era `unique_index`) silently
returned nothing and **fell back to a default**, with no migration, no startup
guard, and no operator alert. It only manifested deep in a login flow. The
changelog documented the change; nothing *detected* the un-rebuilt data.

So the headline goal is not merely enumeration — it is **surfacing index
inconsistency before it degrades behavior.** Enumeration (Part A) and the
persisted manifest (Part B) are the building blocks; the format/topology guard
(§3.4) is the payoff.

The v2.10.0 migration makes gap #1 urgent. The migration guide currently tells
users to rebuild **each index by hand**:

```ruby
User.rebuild_email_lookup        # one call per class, per index
company.rebuild_badge_index
```

That does not scale and requires the operator to enumerate every index manually.
The goal of this proposal is to make this possible instead:

```ruby
# Rebuild every class-level unique index in the app, no internals required:
Familia.unique_indexes.select(&:class_level?).each(&:rebuild!)
```

## 2. Design principle: follow `each_record`

`Familia::DataType::CollectionBase#each_record`
(`lib/familia/data_type/collection_base.rb:70`) is the model to emulate. It lets
callers iterate a reference collection and get **loaded records** back without
knowing about batching, ghost-key filtering, `load_multi`, or pipelining:

```ruby
User.instances.each_record { |user| user.deactivate! }
User.email_lookup.each_record { |user| user.notify! }   # since v2.10.0
```

Two properties we carry forward:

- **It hides the mechanism.** The caller never constructs keys or knows the
  index is a HashKey of `value => identifier`.
- **It is built on a reference DataType** (`class:` + `reference: true`). v2.10.0
  already made `unique_index` hashkeys reference types — the same shape as the
  `instances` set wired up in `Horreum.inherited` (`lib/familia/horreum.rb:176`).

Our descriptors should expose the same affordance: hand the caller a thing they
can `each_record` over, or `rebuild!`, without naming conventions leaking out.

---

## 3. Part A — Project-wide introspection methods

### 3.1 `Familia::IndexDescriptor`

`IndexingRelationship` deliberately does **not** know its owning class. A
project-wide view needs that pairing, plus the behavior that hides the
method-naming conventions. Introduce a thin wrapper (a `Data.define`, matching
the existing `*Relationship` structs):

```ruby
# lib/familia/index_descriptor.rb (sketch)
Familia::IndexDescriptor = Data.define(:owner, :relationship) do
  # Delegate the descriptive fields straight through:
  def field;        relationship.field;        end
  def index_name;   relationship.index_name;   end
  def cardinality;  relationship.cardinality;  end   # :unique | :multi
  def within;       relationship.within;       end
  def scope_class;  relationship.scope_class;  end
  def query?;       relationship.query;        end
  def class_level?; relationship.class_level?; end

  def unique?; cardinality == :unique; end
  def multi?;  cardinality == :multi;  end

  # Stable, human/machine-friendly coordinate, e.g. "User:email_lookup"
  def coordinate; "#{owner.name}#{Familia.delim}#{index_name}"; end

  # --- Behavior that hides internals (the each_record-style affordance) ---

  # Iterate the indexed records. Resolves the right backing collection for the
  # caller so they never touch `owner.send(index_name)` or the `_for` factory.
  #
  #   class-level unique -> owner.<index_name>            (HashKey, reference)
  #   class-level multi  -> owner.<index_name>_for(value) (UnsortedSet, reference)
  #   instance-scoped    -> requires `within:` scope; raises a clear error
  #                         unless a scope instance is supplied
  def each_record(value: nil, scope: nil, **opts, &blk)
    backing(value: value, scope: scope).each_record(**opts, &blk)
  end

  # Rebuild this index from the source of truth (delegates to the generated
  # rebuild_<index_name> method). Powers the v2.10.0 sweep.
  def rebuild!(scope: nil)
    raise Familia::Problem, "#{coordinate} is instance-scoped; pass scope:" if !class_level? && scope.nil?
    target = scope || owner
    target.public_send("rebuild_#{index_name}")
  end

  private

  def backing(value:, scope:)
    # ... resolves HashKey vs UnsortedSet factory vs scoped collection ...
  end
end
```

The point is not the exact body — it is that **all** the conditional knowledge
(`within.nil?`, `cardinality == :unique`, the `_for` factory, scope
requirements) lives *here*, once, instead of in every caller.

### 3.2 `Familia` module helpers

```ruby
module Familia
  # All indexes across every loaded Horreum subclass.
  # Filters are optional and composable.
  def self.index_descriptors(cardinality: nil, class_level: nil, owner: nil)
    members.flat_map do |klass|
      next [] unless klass.respond_to?(:indexing_relationships)
      next [] if owner && klass != owner

      klass.indexing_relationships.filter_map do |rel|
        next if cardinality   && rel.cardinality != cardinality
        next if !class_level.nil? && rel.class_level? != class_level
        IndexDescriptor.new(owner: klass, relationship: rel)
      end
    end
  end

  def self.unique_indexes(**filters) = index_descriptors(cardinality: :unique, **filters)
  def self.multi_indexes(**filters)  = index_descriptors(cardinality: :multi,  **filters)

  # Participation parallel (returns owner + ParticipationRelationship pairs).
  def self.participation_descriptors(owner: nil)
    members.flat_map do |klass|
      next [] unless klass.respond_to?(:participation_relationships)
      next [] if owner && klass != owner
      klass.participation_relationships.map { |rel| [klass, rel] }
    end
  end
end
```

The `respond_to?(:indexing_relationships)` guard mirrors the pattern already
used throughout the codebase (e.g. `update_all_indexes`,
`AuditMethods#audit_unique_indexes`), so this enumerates only classes that
actually use `feature :relationships`.

### 3.3 The v2.10.0 use case, end to end

```ruby
# Rebuild every class-level unique index after upgrading to v2.10.0:
Familia.unique_indexes.select(&:class_level?).each(&:rebuild!)

# Or just visit every indexed record (e.g. to re-validate):
Familia.unique_indexes.select(&:class_level?).each do |idx|
  idx.each_record { |record| record.touch }
end
```

No `respond_to?`, no `send`, no cardinality branching, no key construction in
the caller — the same ergonomics as `each_record` itself.

> **Caveat (inherited from `Familia.members`):** the registry contains every
> `Horreum` subclass that has been **required** — framework models, app models,
> and test classes alike. Run project-wide sweeps after the app is fully loaded.
> See the existing [Introspection](../guides/feature-relationships.md#introspection)
> note.

### 3.4 Detecting stale index data (the boot guard) — gap #3

This is the part that would have caught the incident in §1. The enumeration
above lets us *check* every index, not just list it. The detection predicate
already exists: `Familia::DataType::Serialization#strip_legacy_json_encoding`
(`lib/familia/data_type/serialization.rb:151`) recognizes a legacy
JSON-encoded identifier as `String && length > 2 && start_with?('"') &&
end_with?('"')` and warns at read time. We reuse exactly that predicate (extract
it to a side-effect-free `legacy_json_encoded?(val)` so the read path and the
guard share one definition) instead of inventing new format knowledge.

Add a sampling check to the descriptor and module-level guards:

```ruby
class Familia::IndexDescriptor
  # Sample raw stored values (HRANDFIELD/HSCAN — no deserialize, no warn spam)
  # and report whether any are still in the pre-2.10.0 encoded format.
  def stale_format?(sample: 100)
    return false unless class_level? && unique?     # scoped/multi handled separately
    owner.public_send(index_name).sample_raw_values(sample).any? { |v| Familia.legacy_json_encoded?(v) }
  end
  def format_current?(**o) = !stale_format?(**o)
end

module Familia
  # Indexes whose stored data predates the current format (need a rebuild).
  def self.stale_indexes(sample: 100)
    unique_indexes(class_level: true).reject { |idx| idx.format_current?(sample: sample) }
  end

  # Boot guard / CI smoke test: raise (or warn) if any index is stale.
  def self.assert_indexes_current!(sample: 100, on_stale: :raise)
    stale = stale_indexes(sample: sample)
    return true if stale.empty?
    msg = "Stale unique indexes need rebuild: #{stale.map(&:coordinate).join(', ')} " \
          "(see docs/migrating/v2.10.0.md)"
    on_stale == :warn ? Familia.warn(msg) : raise(Familia::Problem, msg)
    false
  end
end
```

Now the downstream app gets all three of its missing safeguards from one API:

```ruby
# (1) Migration helper — rebuild everything stale, no internals required:
Familia.stale_indexes.each(&:rebuild!)

# (2) Boot-time assertion — sample a known index entry, fail fast on drift:
Familia.assert_indexes_current!            # in an initializer / Familia.boot!

# (3) CI / deploy smoke test — same call, non-fatal:
Familia.assert_indexes_current!(on_stale: :warn)
```

Sampling cost is bounded (`HRANDFIELD`/`HSCAN` of N per index), so the boot guard
is cheap even with many indexes. This is also a natural home in the audit layer:
`Klass.health_check` could fold in `stale_format?` for its own indexes.

---

## 4. Part B — Persisted "clan manifest" (opt-in)

### 4.1 Goal & the meaning of *idempotent*

Persist a representation of the entire clan — every class's fields, identifier
field, indexes, participations, prefix, and logical database — to Redis, such
that **writing it repeatedly converges to the same state**. Idempotency here is
concrete:

1. **Deterministic keys** — the manifest always lives at the same key(s).
2. **Keyed by class name** — class descriptors overwrite (HSET), never append.
3. **Atomic full rewrite** — `DEL` + repopulate inside one `MULTI/EXEC`, so a
   class removed from the codebase disappears from the manifest and readers
   never observe a partial state.
4. **Fingerprint short-circuit** — a content hash gates the write, so re-running
   with unchanged topology is a no-op (and cheap: one read, no write).

N processes booting the same code therefore converge to byte-identical manifest
state.

### 4.2 Configuration (opt-in)

Following the exact `lib/familia/settings.rb` accessor pattern:

```ruby
# defaults (module level)
@persist_manifest = false
@manifest_key     = nil   # resolves to "#{prefix}familia:manifest"

module Familia::Settings
  def persist_manifest(val = nil)
    @persist_manifest = val unless val.nil?
    @persist_manifest || false
  end
  alias persist_manifest? persist_manifest

  def manifest_key(val = nil)
    @manifest_key = val if val
    @manifest_key || [Familia.prefix, 'familia', 'manifest'].compact.join(Familia.delim)
  end
end
```

```ruby
Familia.configure do |config|
  config.persist_manifest = true               # opt-in; default false
  config.manifest_key      = 'myapp:manifest'   # optional override
end
```

**When does the flag write?** Not from `Horreum.inherited` — at inheritance time
the clan is half-loaded and most fields/indexes are not yet declared. Writing
there would persist a torn snapshot. Instead the flag means *"this app maintains
a manifest"*, and the actual write is triggered once after boot, via:

- an explicit call to `Familia.persist_manifest!` (a Rails `after_initialize`,
  a `Familia.boot!`-style hook, or a deploy task), and/or
- an optional `at_exit` safety-net writer guarded by the flag.

This keeps the expensive/atomic operation under the operator's control while the
flag documents intent and enables the safety net. (Auto-writing on first read of
`Familia.manifest` is an alternative; see Open Questions.)

### 4.3 Namespaced manual API

```ruby
Familia.persist_manifest!(force: false)  # write iff fingerprint changed (or force)
Familia.manifest                         # => Hash (read persisted snapshot back)
Familia.manifest_fingerprint             # => String (current in-memory topology hash)
Familia.manifest_drift?                  # => Boolean (persisted vs current differ?)
```

`manifest_drift?` is the high-value verb: a deploy or CI step can assert the
running code's index/participation topology matches what was last persisted —
catching "you added a `unique_index` but never ran the rebuild" before it bites.
It also gives the audit layer (`Familia::Horreum::Management`) a project-wide
signal to complement its per-class `health_check`.

### 4.4 Redis data structures

The manifest is structured, partially-queryable config. Use **three** keys,
written together in one transaction:

| Key | Type | Contents | Why |
|-----|------|----------|-----|
| `…:manifest` | **HashKey** | field = `"User"`, value = JSON class descriptor (`fields`, `identifier_field`, `prefix`, `logical_database`, `features`, `indexes`, `participations`) | O(1) per-class read (`HGET`), atomic full read (`HGETALL`), overwrite-keyed-by-name = idempotent |
| `…:manifest:indexes` | **HashKey** | field = `"User:email_lookup"`, value = JSON (`field`, `cardinality`, `within`, `query`, `dbkey`/pattern) | Enumerate **every index in the app** without parsing each class blob — directly serves the v2.10.0 sweep, and carries the backing `dbkey` so a migration can act without re-deriving it |
| `…:manifest:meta` | **StringKey (JSON)** | `{ familia_version, fingerprint, generated_at, ruby_version }` | Fingerprint short-circuit + provenance |

Notes:

- **Build on Familia, but keep the manifest out of the clan it describes.** Write
  via `Familia.dbclient` directly (HashKey/StringKey commands) rather than
  modeling the manifest as a `Horreum` subclass — otherwise the manifest would
  register in `Familia.members` and appear in its own snapshot. (A
  `Familia::Manifest < Horreum` is possible but must be excluded from
  enumeration; the direct approach avoids the meta-recursion entirely.)
- The `:indexes` hash is intentionally redundant with data inside the class
  blobs — it is a denormalized secondary index for the common "iterate all
  indexes" query, the same trade-off Familia makes elsewhere (reverse
  participation indexes).

### 4.5 Advanced Redis features in play

- **`MULTI`/`EXEC` transaction** wrapping `DEL …:manifest`, `DEL …:manifest:indexes`,
  the `HSET`s, and the meta `SET` — readers see the old manifest or the new one,
  never a mix. Familia already provides `transaction`/`pipelined` plumbing.
- **Fingerprint guard** — `persist_manifest!` computes `SHA256(canonical_json)`
  (sorted keys for stability), compares against `…:manifest:meta.fingerprint`,
  and returns early unless it differs or `force: true`. This is what makes
  repeated boots cheap and idempotent.
- **Atomic swap on rewrite** — the `DEL`+repopulate inside the transaction prunes
  classes that no longer exist, so the persisted set always equals the current
  clan (no stale drift accumulating).
- **`HSCAN`** for reading back very large manifests without blocking.
- **Key namespacing under `Familia.prefix`** so multiple apps / logical DBs sharing
  a server never collide.
- **No expiration** (`default_expiration` 0) — the manifest is durable config.

### 4.6 Sketch

```ruby
module Familia
  module Manifest
    module_function

    def fingerprint = Digest::SHA256.hexdigest(JSON.generate(canonical))

    def persist!(force: false)
      meta_key = "#{Familia.manifest_key}:meta"
      current  = fingerprint
      stored   = (JSON.parse(Familia.dbclient.get(meta_key)) rescue {})['fingerprint']
      return false if !force && stored == current   # idempotent short-circuit

      Familia.dbclient.multi do |tx|
        tx.del(Familia.manifest_key, "#{Familia.manifest_key}:indexes")
        canonical[:classes].each { |name, desc| tx.hset(Familia.manifest_key, name, JSON.generate(desc)) }
        Familia.index_descriptors.each do |idx|
          tx.hset("#{Familia.manifest_key}:indexes", idx.coordinate, JSON.generate(index_blob(idx)))
        end
        tx.set(meta_key, JSON.generate(version: Familia::VERSION, fingerprint: current,
                                       generated_at: Familia.now, ruby_version: RUBY_VERSION))
      end
      true
    end

    def canonical
      classes = Familia.members.each_with_object({}) do |k, h|
        next unless k.name && k.respond_to?(:fields)   # skip anonymous/internal
        h[k.name] = describe(k)
      end
      { classes: classes.sort.to_h }   # sorted => stable fingerprint
    end
  end

  def self.persist_manifest!(**o) = Manifest.persist!(**o)
  def self.manifest               = dbclient.hgetall(manifest_key).transform_values { |v| JSON.parse(v) }
  def self.manifest_fingerprint   = Manifest.fingerprint
  def self.manifest_drift?        = (manifest_fingerprint != (JSON.parse(dbclient.get("#{manifest_key}:meta"))['fingerprint'] rescue nil))
end
```

---

## 5. How the two parts compose

`index_descriptors` is the single source the manifest serializes from (§4.6
calls it directly), so the persisted `:indexes` hash and the live
`Familia.unique_indexes` describe the *same* coordinates. A migration can drive
off either:

```ruby
# Live (post-boot):
Familia.unique_indexes.select(&:class_level?).each(&:rebuild!)

# From the persisted manifest (e.g. a standalone migration process that loads
# the same models): read coordinates, act on the backing dbkeys.
```

And `manifest_drift?` ties back to introspection: it is literally
"does `fingerprint(index_descriptors + participation_descriptors + fields)` match
what we persisted?"

---

## 6. Implementation plan

1. **`Familia::IndexDescriptor`** (`lib/familia/index_descriptor.rb`) + the
   `each_record`/`rebuild!` delegation. Tryouts covering class-level unique,
   class-level multi, and instance-scoped (error without scope).
2. **`Familia.index_descriptors` / `unique_indexes` / `multi_indexes` /
   `participation_descriptors`** on the module. Tryouts for the v2.10.0 sweep.
3. **Format guard (§3.4):** extract `Familia.legacy_json_encoded?`, add
   `IndexDescriptor#stale_format?`, `Familia.stale_indexes`, and
   `Familia.assert_indexes_current!`. Tryouts seeding a legacy-encoded value and
   asserting it is detected (and cleared after `rebuild!`). **This is the
   highest-priority slice — it closes the incident gap.**
4. **Docs:** promote the project-wide sweep in
   [feature-relationships.md#introspection](../guides/feature-relationships.md#introspection)
   from "compose it yourself" to "use `Familia.unique_indexes`," and document the
   boot guard.
5. **`Familia::Manifest`** + config option + `persist_manifest!`/`manifest`/
   `manifest_drift?`. Tryouts for idempotency (write twice ⇒ one effective
   write), drift detection, and atomic-rewrite pruning.
6. **Changelog fragment** under `changelog.d/`.

Steps 1–4 are independently shippable and directly resolve the incident; step 5
(the manifest) builds on the same descriptors for durable auditing/recovery.

## 7. Open questions

- **Write trigger.** Explicit `persist_manifest!` only, `at_exit` safety net, or
  lazy-on-first-read? (Leaning: explicit + opt-in `at_exit`; never on `inherited`.)
- **Manifest as Horreum vs raw dbclient.** Raw avoids meta-recursion (§4.4);
  worth the small loss of DataType ergonomics?
- **Descriptor naming.** `IndexDescriptor` vs reusing/extending
  `IndexingRelationship` with an `owner`. A separate wrapper keeps the existing
  struct unchanged and serializable.
- **Scope of the snapshot.** Indexes + participations + fields is the obvious
  core; do we also capture `related_fields`, feature options, encryption key
  versions?

## 8. Non-goals

- **The "migration helper" here is deliberately lightweight** — a detect
  (`stale_indexes`) + rebuild (`rebuild!`) sweep over existing index machinery.
  It is *not* a versioned schema-migration engine (that is
  `lib/familia/migration/`), and it does not transform record data beyond
  re-deriving indexes from the source of truth.
- Not JSON-Schema validation (that is the existing `Familia::SchemaRegistry`).
- Not a replacement for per-class `health_check`/audit — the manifest is a
  topology snapshot, and the boot guard a format check; neither replaces the
  deeper per-class data-consistency audit (they complement it, §3.4).

## See Also

- [Relationships — Introspection](../guides/feature-relationships.md#introspection)
- `lib/familia/data_type/collection_base.rb` — `each_record` (design inspiration)
- `lib/familia/horreum.rb:176` — the `instances` reference-set precedent
- `lib/familia/horreum/management/` — the audit/repair layer this complements
