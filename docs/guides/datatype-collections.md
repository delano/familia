# docs/guides/datatype-collections.md
---

# DataType - Collection classes

UnsortedSet, Sorted Set, List, and Hash data types all include the `Collection` module. This guide covers two performance-sensitive concerns: writing many elements efficiently (a single bulk command instead of one round-trip per element), and iterating large collections efficiently via `each` and `each_record`.

## Bulk writes — single round-trip mutations

Collection mutations are **immediate** — every call hits Valkey/Redis right away, unlike scalar `field` setters which are deferred until `save`. Each call also runs `warn_if_dirty!` and cascades expiration. (See the write-model notes in `AGENTS.md` for the deferred-vs-immediate split.)

Multi-element adds issue **one** command for the whole batch, not one per element. Populating a large collection is therefore a single round-trip even without an explicit pipeline.

The argument shape follows the collection's structure, and is consistent across the codebase:

- **Value-only** collections (`UnsortedSet`, `ListKey`) take a **variadic splat**; arguments are flattened and `nil`-compacted.
- **Keyed/pair** collections (`HashKey` is `field => value`, `SortedSet` is `member => score`) take a **single Hash** via `update` (aliased `merge!`), raising `ArgumentError` on a non-Hash.

| Type | Bulk method | Call shape | Redis command |
|---|---|---|---|
| `UnsortedSet` | `add(*values)` | `tags.add(:a, :b, :c)` | one `SADD` |
| `ListKey` | `push(*values)` / `unshift(*values)` | `log.push(1, 2, 3)` | one `RPUSH` / `LPUSH` |
| `HashKey` | `update(hash)` / `merge!` | `cfg.update(a: 1, b: 2)` | one `HMSET` |
| `SortedSet` | `update(hash)` / `merge!` | `board.update("alice" => 1000, "bob" => 850)` | one `ZADD` |

```ruby
tags.add(:ruby, :redis, :valkey)              # 1 SADD, returns self
log.push("a", "b", "c")                        # 1 RPUSH → [a, b, c]
board.update("alice" => 1000, "bob" => 850)    # 1 ZADD, returns new-member count (2)
board.merge!("alice" => 1200)                  # 1 ZADD, score updated → returns 0
```

Behavior notes:

- **Ordering**: `push` preserves argument order; `unshift` prepends each element in turn, so `unshift(a, b, c)` leaves the list head as `c, b, a` (Redis `LPUSH` semantics — unchanged from the prior per-element implementation). Sets are unordered; sorted sets order by score.
- **Empty input is a no-op**: `add()` / `push()` / `update({})` issue no command. Set/list adds return `self`; `SortedSet#update` returns `0`.
- **`SortedSet#add(val, score, …)` is unchanged and not bulk** — it takes a single member plus score and the conditional ZADD options (`nx:`, `xx:`, `gt:`, `lt:`, `ch:`). An Array passed as `val` is stored as one JSON-encoded member, not exploded into many. Use `update`/`merge!` for bulk insertion.

The iteration methods `each` and `each_record` efficiently handle large collections by paginating through Valkey/Redis data structures, but they serve different purposes and yield different results. Here's how the two iterate, using `ModelClass.instances` (a `SortedSet` with `reference: true`) as the running example.

## `each` — yields **members** (identifiers, raw strings)

`each` is implemented per type. For the `instances` SortedSet, it pages through the ZSET with either `ZRANGEBYSCORE` (when `since:`/`until:` are given) or `ZSCAN` (unbounded), yielding one deserialized member at a time.

```mermaid
flowchart TD
  Caller["ModelClass.instances.each { |id| ... }"] --> EachImpl["SortedSet#each"]
  EachImpl --> Decide{since/until?}
  Decide -- yes --> ZRBS["ZRANGEBYSCORE key min max LIMIT 0 batch_size WITHSCORES"]
  Decide -- no --> ZSCAN["ZSCAN key cursor COUNT batch_size"]
  ZRBS --> Page["Page of raw members"]
  ZSCAN --> Page
  Page --> Yield["yield deserialize_value(member)"]
  Yield --> More{more pages?}
  More -- yes --> Decide
  More -- no --> Done["return self"]
```

Per-type variations:
- `ListKey#each` — paginates with `LRANGE start stop` (no SCAN equivalent)
- `UnsortedSet#each` / `HashKey#each` — `SSCAN` / `HSCAN`, optional `matching:` glob
- `SortedSet#each` — `ZRANGEBYSCORE` (bounded) or `ZSCAN` (unbounded)

You get **identifiers only**. No record loading. One Redis round-trip per page.

## `each_record` — yields **loaded Horreum records**

`each_record` is defined once in `CollectionBase` and delegates to `each` to collect identifiers, then batches them into `record_class.load_multi` (pipelined `HGETALL`s), filters ghosts, and yields the live records.

```mermaid
flowchart TD
  Caller["ModelClass.instances.each_record { |rec| ... }"] --> ER["each_record(batch_size, pipeline, **filters)"]
  ER --> Validate{"pipeline <= batch_size?"}
  Validate -- no --> Raise["raise ArgumentError"]
  Validate -- yes --> CallEach["each(**filters) do |member|"]
  CallEach --> Extract["id = member.is_a?(Array) ? member.last : member"]
  Extract --> Buffer["buffer << id"]
  Buffer --> Full{"buffer.size >= batch_size?"}
  Full -- no --> CallEach
  Full -- yes --> Load["record_class.load_multi(ids)  -- pipelined HGETALLs"]
  Load --> Compact["live = records.compact  -- drop ghosts"]
  Compact --> Mode{pipeline?}
  Mode -- nil --> Serial["live.each { |r| block.call(r) }"]
  Mode -- positive --> Pipe["live.each_slice(pipeline) do |group|<br/>record_class.pipelined { group.each &block }<br/>end"]
  Serial --> Clear["buffer.clear; resume each"]
  Pipe --> Clear
  Clear --> CallEach
  CallEach -. each exhausted .-> Flush["process_batch(buffer) if any remain"]
  Flush --> Return["return self"]
```

### Concrete timeline for `User.instances.each_record(batch_size: 100, pipeline: 25) { |u| u.touch! }`

```
SortedSet#each (ZSCAN page 1, 100 ids)
   ├─ buffer fills to 100
   ├─ load_multi(ids)        → 1 pipeline of 100 HGETALLs
   ├─ compact ghosts          → e.g. 97 live records
   ├─ slice(25):
   │     pipelined { 25 × u.touch! }   ← 1 Redis pipeline
   │     pipelined { 25 × u.touch! }   ← 1 Redis pipeline
   │     pipelined { 25 × u.touch! }   ← 1 Redis pipeline
   │     pipelined { 22 × u.touch! }   ← 1 Redis pipeline
   └─ buffer.clear
SortedSet#each (ZSCAN page 2, 100 ids)
   └─ … repeat …
SortedSet#each exhausted
   └─ flush any remaining buffered ids the same way
```

## Key differences

| Aspect | `each` | `each_record` |
|---|---|---|
| Yields | raw identifier (or `[field, value]` for `HashKey`) | loaded Horreum instance |
| Redis ops per yield | 0 extra (already paged) | amortized `HGETALL` via `load_multi` batch |
| Requires `reference: true` + `:class` | no | yes (raises `Familia::Problem` otherwise) |
| Ghost handling | yields the dangling id | `compact` drops them silently |
| Write pipelining | not built-in | `pipeline:` groups block-body writes into `pipelined` blocks |
| Filters | type-specific (`since:`, `matching:`, …) | forwarded to underlying `each` |

So `each_record` is a thin orchestration layer: it leans on the type's own `each` for read pagination, then layers (1) batched record hydration and (2) optional write pipelining on top.

### Which collections support `each_record`?

`each_record` needs a collection declared with `class:` + `reference: true`. The
collections Familia generates for you already satisfy this, so `each_record`
works on them out of the box:

- `ModelClass.instances` — the per-class timeline (see Horreum).
- `unique_index` / `multi_index` lookups — the index hashkey/set points at the indexed class.
- `participates_in` / `class_participates_in` collections — point at the participant class.

A collection you declare by hand (`sorted_set :foo`, `set :bar`, …) stores
JSON-encoded values by default and is **not** a reference type; calling
`each_record` on it raises `Familia::Problem`. Add `class:` + `reference: true`
to opt in. Note that if you pre-declare a collection that `participates_in`
would otherwise auto-create, your hand-declared options win — declare it as a
reference type yourself if you want `each_record` on it.

## Choosing a `pipeline` mode

`each_record` has two dispatch modes, controlled by `pipeline:`. The parameter answers a single question: **may the dispatch loop wrap your block in a `pipelined { }`?**

| Value | Dispatch | Use when the block… |
|---|---|---|
| `nil` (default) | Each record runs in its own connection context, no pipeline wrapper | …reads, OR calls `save` / `commit_fields` / `transaction` / anything with its own internal MULTI |
| positive integer | Groups of `pipeline` records run inside `record_class.pipelined { ... }` | …only issues fast writers (`record.field!`) that tolerate being queued |

Note: `pipeline: 0` raises `ArgumentError`. Use `pipeline: nil` to disable pipelining.

The read-only case and the serial-write case collapse into the same mode because both require **immediate** execution with real return values. Wrapping `save` in an outer `pipelined` would either return `Redis::Future` objects or raise `ConflictingContextError` when `save`'s internal transaction tries to open.

### The three idiomatic patterns

```ruby
# 1. Read-only iteration — the default (pipeline: nil) is correct
User.instances.each_record do |user|
  puts "#{user.email} #{user.last_login}"
end

# 2. Serial writes — the default (pipeline: nil) is required for save / commit_fields / transaction
User.instances.each_record do |user|
  user.score = recompute(user)
  user.save
end

# 3. Pipelined fast writers — opt-in optimization
User.instances.each_record(pipeline: 50) do |user|
  user.last_seen_at! Familia.now   # single HSET, safe to queue in pipeline
end
```

### Pipelining footgun

If you enable pipelining and your block reads from a related collection (e.g. `user.sessions.size`), that read is queued into the pipeline and returns a `Redis::Future` rather than a value. Omit the `pipeline:` parameter (or explicitly pass `pipeline: nil`) whenever the block needs real return values from Redis.
