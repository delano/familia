# AGENTS.md

Guidance for AI coding agents working in this repository.

## Development Commands

- **Install**: `bundle install`
- **Docs**: `bundle exec yard`
- **Lint**: `bundle exec rubocop`
- **Test**: `bundle exec try` (auto-discovers `*_try.rb` / `*.try.rb`)

### Testing (Tryouts v3)

Each file has optional setup, testcases, and optional teardown. A testcase is a
`##` description line, Ruby code, then one or more expectation comments
(`#=>`, `#==>`, `#=:>`, `#=!>`, ...). The last expression is the result.
Instance variables (`@var`) persist across sections; locals do not. Write plain
realistic code; avoid mocks and test DSL.

Run with `--agent` for token-efficient output (`--agent-focus summary|first-failure|critical`).
See `bundle exec try --help` for the full CLI, framework integration (`--rspec`,
`--minitest`), and debugging flags.

### Changelog

Add a changelog fragment (RST) with each user-facing change. See @changelog.d/README.md

### Known Issues & Quirks

- **Reserved field names**: `ttl`, `db`, `valkey`, `redis` cannot be field names — use prefixed alternatives.
- **Empty identifiers**: Cause a stack overflow in key generation — validate before operations.
- **Lazy initialization**: Connection chains and field collections initialize lazily without synchronization (generally safe under the GIL, not guaranteed).

### Debugging

Ask the user for real-time database command monitoring (commands with timestamps
and database numbers, live) when debugging multi/exec, pipelining, or
`logical_database` issues.

## Architecture

**Familia** is a Valkey-compatible ORM providing Ruby object storage with
expiration, safe dumping, and quantization.

### Core Classes

- **`Familia::Horreum`** (`lib/familia/horreum.rb`) — base class for Valkey-backed objects (ActiveRecord-like). Field definitions, data type relationships, lifecycle.
- **`Familia::DataType`** (`lib/familia/data_type.rb`) — base for type wrappers (String, JsonStringKey, List, UnsortedSet, SortedSet, HashKey). Each type in `lib/familia/data_type/types/`.
- **`Familia::Base`** (`lib/familia/base.rb`) — shared module for both, hosts the feature system.

Features (Expiration, SafeDump, Relationships, ...) are modules mixed into
classes via `Familia::Base`. See `lib/familia/features/`.

### Defining a Model

```ruby
class User < Familia::Horreum
  field :email        # scalar field
  list :sessions      # Valkey/Redis list
  set :tags           # set
  zset :metrics       # sorted set
  hashkey :settings   # hash
end
```

Identifier strategies:

```ruby
identifier_field :email                      # symbol
identifier ->(user) { "user:#{user.email}" } # proc
identifier [:type, :email]                    # array
```

Connection handling lives in `lib/familia/connection.rb` and `lib/familia/settings.rb`;
select databases with the `logical_database` class method (URI configuration supported).

### Initialization: do not override `initialize` without `super`

Familia's `initialize` sets fields from kwargs, then sets up DataType objects,
then calls your `init` hook. Overriding `initialize` without `super` breaks
related-field setup.

Apply defaults in the `init` hook with `||=` (never `=`, which would overwrite
values Horreum already set from kwargs):

```ruby
class User < Familia::Horreum
  field :objid
  field :email

  def init
    @objid ||= SecureRandom.uuid
  end
end

User.new(email: 'test@example.com').objid # => generated UUID
```

Only override `initialize` (with `super`) when you must transform arguments
before Horreum processes them.

## Serialization

Horreum fields are JSON-encoded for storage and JSON-decoded on load, preserving
Ruby types (Integer, Boolean, String, Float, Hash, Array, nil). `false` and `0`
are preserved; only `nil` values are omitted from storage.

| Context | Serialize | Ruby `"UK"` stored as | Ruby `123` stored as |
|---|---|---|---|
| Horreum `field` | `serialize_value` (JSON) | `"\"UK\""` | `"123"` |
| `StringKey` | `.to_s` (raw) | `"UK"` | `"123"` |
| `JsonStringKey` | JSON dump | `"\"UK\""` | `"123"` |
| List/Set/SortedSet/HashKey values | `serialize_value` (JSON) | `"\"UK\""` | `"123"` |

`StringKey` uses raw `.to_s` (not JSON) to support `INCR`/`DECR`/`APPEND`; a
Horreum string field stores `"UK"` as `"\"UK\""` while a `StringKey` stores it as
`"UK"`. Use `instance.debug_fields` to compare Ruby values vs stored JSON.

Database keys are generated as `classname:identifier:fieldname` (aka dbkey).
DataType instances are frozen after instantiation.

## Write Model: Deferred vs Immediate

**Scalar fields** (`field`) use deferred writes: normal setters
(`user.name = "Alice"`) only touch memory until `save`/`commit_fields`/`batch_update`.
Fast writers (`user.name! "Alice"`) do an immediate `HSET`.

**Collection fields** (`list`, `set`, `zset`, `hashkey`) use immediate writes:
every mutator (`add`, `push`, `remove`, `clear`, `[]=`) hits Redis right away.
Collections live on separate keys from the object hash.

**Safe pattern — scalars first, then collections:**

```ruby
plan.name = "Premium"
plan.save  # HMSET for scalar fields

plan.save_with_collections do
  plan.features.clear
  plan.features.add("sso")
end
```

Mutating collections before `save` is unsafe: if `save` raises, the collections
are already mutated.

**Atomic pattern — scalars and collections in one MULTI/EXEC:**

```ruby
plan.atomic_write do
  plan.name = "Premium"   # deferred: queued as HMSET
  plan.features.clear     # immediate: queued as DEL in the open MULTI
  plan.features.add("sso")
end
```

`atomic_write` composes the `transaction` infrastructure so every command lands
in one MULTI/EXEC; collection mutations auto-route into the open transaction via
`Fiber[:familia_transaction]`. Constraints:

- All related DataTypes must share the parent's `logical_database`, else `Familia::CrossDatabaseError` (fall back to `save_with_collections`). MULTI/EXEC is single-database only.
- Cannot nest inside another `transaction`/`atomic_write` (`Familia::OperationModeError`).
- Collection return values inside the block are `Redis::Future` — do not inspect before EXEC.

**Factory — `build` for create-and-populate:**

```ruby
user = User.build(email: "alice@example.com") do |u|
  u.name = "Alice"        # deferred scalar
  u.tags.add("admin")     # folded into the same MULTI
end
```

`build` is class-level sugar over `new` + `atomic_write` with create-only
semantics: raises `RecordExistsError` if the identifier exists, same
single-database constraint. Without a block it degenerates to `new(...).save`.
For upsert, use `save`/`save_with_collections`.

## Instances Timeline

Every Horreum subclass has a class-level `instances` sorted set — a timeline of
last-write timestamps (ZADD score), not a registry.

- **Touch** (`touch_instances!`): `save`/`save_if_not_exists!` (via `persist_to_storage`), `commit_fields`, `batch_update`, `save_fields`, fast writers.
- **Remove**: instance `destroy!` (`remove_from_instances!`), class `destroy!(id)`, lazy `cleanup_stale_instance_entry` in `find_by_dbkey`.
- **Ghosts**: a hash key expiring via TTL leaves a stale identifier in `instances`. `find_by_dbkey` prunes on access; raw enumeration (`instances.members`) still sees ghosts.
- **`in_instances?(id)`** — fast O(log N), may report ghosts or miss non-Familia objects. **`exists?(id)`** — authoritative hash-key check (round-trip). `load`/`find_by_id` read the hash key directly and bypass `instances`.

## Thread Safety

DataType instances are frozen (immutable). Configure module-level settings once
at startup, before threads spawn. `Familia.start_monitoring!` tracks contention.
Tests and contention patterns live in `try/thread_safety/`.
