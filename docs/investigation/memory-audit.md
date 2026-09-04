# Familia memory audit (v2.11.1)

Investigation of [#309 — Participation permission query (`<collection>_with_permission`)
is O(N) memory](https://github.com/delano/familia/issues/309), broadened to the
question that motivated it: **OneTimeSecret shows a slow per-process memory hole —
Ruby RSS climbs over weeks. Is the cause in Familia?**

This document diagnoses #309 precisely and audits the rest of `lib/` for memory
problems. It is a *diagnosis*, not a set of fixes; each finding carries a fix
sketch and the remediation section prioritises them, but this investigation
itself changes no runtime behaviour — it adds only this write-up and the two
executable proofs below. (Other, unrelated changes ride along in the 2.11.1
release branch this landed on; those are tracked in `CHANGELOG.rst`.) The code
artifacts here are two executable proofs in `try/investigation/`:
`process_memory_leak_proof.rb` reproduces the four latent per-process leaks
(Category A) in pure Ruby, and `memory_leak_proof.rb` reproduces the Redis-side
orphan and O(N) high-water-mark findings (Categories B/C) against a live Redis.

For the separate class-level `unique_index` rebuild incident—its causal chain
and implementation plan—see [Rebuild memory incident: class-level unique
indexes](rebuild-memory-incident.md). It is distinct from the fixed permission
query in #309, which is documented below.

## Method

Eight focused audits ran in parallel over `lib/`, each owning one vector
(#309; class-level/global state; connection & fiber-local lifecycle; runtime
method/module generation; encryption & transient fields; relationships/indexing
Redis-side orphans; whole-collection materialization; logging/instrumentation).
Every candidate was then classified adversarially against a two-axis rubric and
only reported if it survived a refutation attempt. Prior art from the
`fix/memory-leak` investigation branch (findings F1–F4 and its Redis-side proof)
was confirmed against current 2.11.1 code rather than restated, and that proof —
`try/investigation/memory_leak_proof.rb` — is consolidated onto this branch
alongside this write-up so the evidence and the diagnosis no longer live apart.

## TL;DR

**Familia has no unconditional, default-configuration per-process memory leak.**
Its Ruby-heap discipline is strong: there are no `@@` class variables anywhere;
every class-level structure is keyed on a load-time-finite set (class / field /
feature / algorithm / section names), is per-instance and GC-reclaimable, is
fiber-local and cleared in an `ensure`, or lives Redis-side.

The OTS symptom — **per-process RSS growth over weeks** — can only be explained by
a structure that is *Ruby-process* **and** *permanently, unboundedly retained*.
Exactly four such structures exist, and **all four are latent**: each is an
append-only registry with no eviction path that Familia itself never grows —
each is armed only by a specific *application* call pattern. In descending order
of likelihood for OTS:

| # | Latent leak | Fires when the app… | Evidence |
|---|-------------|---------------------|----------|
| A1 | Encryption request-key cache keyed on `record.identifier` (`encryption/manager.rb:146-167`) | enables key caching at a scope broader than one request | proof A1 |
| A2 | `reconnect!` re-registers Redis middleware (`connection/middleware.rb:91-94`) | enables DB logging/counter **and** calls `reconnect!` repeatedly | proof A2 |
| A3 | `Instrumentation.@hooks` append-only arrays (`instrumentation.rb:56-112`) | registers instrumentation hooks per-request / on reload | proof A3 |
| A4 | `Familia.members` strong-ref subclass registry (`horreum.rb:173`) | defines `Horreum` subclasses at runtime (per request/tenant) | proof A4 |

Everything else the audit surfaced is either a **transient O(N) spike** (#309 and
its siblings — Ruby-side but GC-reclaimable) or **Redis-side orphan accumulation**
(real dataset-growth debt, but the wrong locus for a process-RSS climb).

**Most probable Familia-side cause for OTS: A1.** OTS is a secrets application that
derives a per-record key for every encrypted field; if it has opted into key
caching anywhere other than a strictly per-request `with_request_cache` block,
the cache retains one derived key per distinct secret, forever — precisely a
slow, weeks-long RSS climb of key material. If none of A1–A4 matches OTS's actual
usage, the leak is most likely in OTS's own code (out of scope for this audit),
with transient-spike high-water-mark ratcheting (Category B) as the runner-up
in-gem explanation.

## Classification framework

Two axes decide whether a finding can be the OTS cause:

- **Locus** — *Redis-side* (grows the Redis dataset/keyspace, not the Ruby
  process) vs *Ruby-process* (grows Ruby heap / RSS).
- **Persistence** — *transient* (a per-call spike GC reclaims after return) vs
  *permanent-unbounded* (retained for the process lifetime, growing without
  bound) vs *bounded* (capped, or keyed on a finite set).

`matches_ots_symptom` is true **only** for Ruby-process **and** permanent-unbounded
**and** keyed on values that grow with distinct runtime data over the process
lifetime. A transient O(N) spike does not qualify (GC frees it). A Redis-side
orphan does not qualify (it grows the server dataset, not the client process).
This is why a large fraction of "scary-looking" findings are correctly *not* the
OTS cause — and why the honest answer is a short list of latent registries rather
than a single smoking gun.

One important caveat sits between Category A and B: a **transient** O(N) spike over
a collection whose size **grows over time**, hit on a hot or periodic path, keeps
raising the RSS high-water mark; with glibc/Ruby heap fragmentation the process
may never return those pages to the OS. That *masquerades* as a slow leak. It is
bounded-per-call retention, not unbounded retention — but operationally it can
look identical to A1–A4. Category B calls out which sites have that growing-N,
hot-path shape.

---

## Category A — latent per-process leaks (the OTS suspects)

All four are `ruby-process` + `permanent-unbounded`, append-only, with no eviction
API — but Familia never drives the trigger. Reproduced in
`try/investigation/process_memory_leak_proof.rb` (pure Ruby, no Redis).

### A1 — Encryption request-key cache is unbounded in cache-key cardinality

- **Where:** `lib/familia/encryption/manager.rb:146-167`; lifecycle in
  `lib/familia/encryption/request_cache.rb:36-55`; context shape in
  `lib/familia/features/encrypted_fields/encrypted_field_type.rb:183-189`.
- **Mechanism:** when `Fiber[:familia_request_cache_enabled]` is set,
  `derive_key_without_increment` stores the derived key at
  `cache_key = "#{algorithm}:#{version}:#{effective_salt}:#{context}"` where
  `context = "#{record.class.name}:#{@name}:#{record.identifier}"` (+ optional
  per-record entropy). Cardinality is therefore `algorithm(≈2) × version(few) ×
  salt(few) × field(finite) × record.identifier(UNBOUNDED)`. The value is 32 bytes
  of key material plus the key string; roughly 100–300 B retained per
  distinct (record, field).
- **Locus/Persistence:** ruby-process; permanent-unbounded **only** if enabled
  outside a per-request boundary. Also a **security** locus (retained key
  material).
- **Default is safe:** the flag defaults `nil`; the cache Hash is never even
  allocated, and the gem never enables it internally.
- **Opt-in is safe:** `with_request_cache` wipes on entry **and** in an `ensure`
  on exit, so a pooled fiber begins and ends each request empty (this is the
  #310-S6 defence documented at `request_cache.rb:8-13`).
- **The leak:** an app that sets `Fiber[:familia_request_cache_enabled] = true`
  once on a long-lived pooled server fiber, or wraps a worker loop rather than a
  single request, never clears the Hash. Proof A1 shows it growing to exactly one
  entry per distinct record and staying (vs. `nil` after `with_request_cache`).
- **Why this is the top OTS suspect:** OTS derives a per-secret key for every
  encrypted field; `record.identifier` is per-secret and unbounded over time; the
  retained object is key material; the growth profile is a slow weeks-long climb.
- **Fix sketch:** (1) drop the unbounded `record.identifier` dimension from the
  cache key, or cap the cache (small LRU); (2) refuse to populate unless an active
  `with_request_cache` frame exists (a depth counter), so directly setting the
  Fiber flag can't create an unmanaged cache; (3) document that `Fiber[...]`
  storage is inherited by child fibers.

### A2 — `reconnect!` re-registers Redis middleware on every call

- **Where:** `lib/familia/connection/middleware.rb:87-107` (reset+recall),
  `:113-136` (`register_middleware_once`), `RedisClient.register` at `:121`/`:129`;
  guard flags initialised in `lib/familia/connection.rb:20-22`.
- **Mechanism:** `register_middleware_once` is normally idempotent (guarded by
  `@logger_registered`/`@counter_registered`, once at boot). `reconnect!` sets
  those flags back to `false` and calls it again, so both
  `RedisClient.register(DatabaseLogger)` and `RedisClient.register(DatabaseCommandCounter)`
  re-run. `RedisClient.register` appends to a **process-global** middleware list
  with no dedup and no unregister API; the module is included into every
  subsequently built client's middleware chain and invoked on every command.
- **Locus/Persistence:** ruby-process (the growth is in `RedisClient`'s registry,
  outside `lib/`); permanent-unbounded **only** if DB middleware is enabled **and**
  `reconnect!` runs repeatedly (failover, timers, per-error reconnection).
- **Proof A2:** 5 `reconnect!` calls → 10 `RedisClient.register` invocations.
- **Fix sketch:** do not clear the registration flags in `reconnect!`
  (`middleware.rb:92-93`); its legitimate job is to bump `middleware_version` and
  drop `@connection_chain` so new connections pick up already-registered
  middleware. Or track "already ever registered" module-side and check
  `RedisClient` membership before appending.

### A3 — `Instrumentation.@hooks` arrays are append-only with no unregister

- **Where:** `lib/familia/instrumentation.rb:32-37` (four `Concurrent::Array`s),
  appends at `:56` (`on_command`), `:73` (`on_pipeline`), `:94` (`on_lifecycle`),
  `:112` (`on_error`).
- **Mechanism:** each `on_*` does `@hooks[type] << block` with no dedup, no cap,
  and **no `off_*`/`clear` method anywhere in `lib/`**. Every registered block is
  retained forever, invoked on every matching command — and each is a closure that
  can pin whatever its defining scope captured (request-scoped objects included).
- **Locus/Persistence:** ruby-process; permanent-unbounded **only** if hooks are
  registered repeatedly (per-request, per-connection, on class reload). Bounded if
  registered once at boot.
- **Familia never grows it:** the gem only ever calls the `notify_*` side
  (`horreum.rb:260`, `persistence.rb:140/597`, the middleware, `serialization.rb:232`),
  which *iterates* hooks and never appends. Growth requires consumer misuse.
- **Proof A3:** 2000 `on_command` registrations all retained; no removal API.
- **Fix sketch:** add `off_*`/`clear_hooks!`, or key hooks by a caller-supplied
  name so re-registration replaces rather than appends; document boot-time-only
  registration.

### A4 — `Familia.members` pins every `Horreum` subclass forever

- **Where:** append at `lib/familia/horreum.rb:173` (`Familia.members << member`);
  array at `lib/familia.rb:43`; the only removers (`unload_member`,
  `clear_anonymous_members`) at `lib/familia.rb:116-130`, documented as
  test-cleanup helpers.
- **Mechanism:** the `inherited` hook strong-references every subclass, so the
  class and its generated singleton methods (`:instances` sorted set, etc.) can
  never be GC'd. Bounded for a static model set defined once at boot; a permanent
  unbounded leak iff the app mints `Horreum` subclasses at runtime.
- **Locus/Persistence:** ruby-process; permanent-unbounded **only** under runtime
  subclassing. The gem contains **zero** `Class.new`/`Struct.new`, so it never
  self-triggers this.
- **Proof A4:** 50 anonymous subclasses appended, all survive a full GC; only the
  manual `clear_anonymous_members` helper evicts them.
- **Fix sketch:** store members in an `ObjectSpace::WeakMap`/set-of-weakrefs, or
  skip registering anonymous (`member.name.nil?`) classes the way
  `Migration::Base.inherited` already does (`migration/base.rb:81`).

---

## Category B — transient O(N) materialization spikes (incl. #309)

Ruby-process but GC-reclaimable: each site assigns to a method-local that is
returned/consumed then dropped. **None writes its result into a class-level or
process-lifetime structure** (verified). So `matches_ots_symptom = FALSE` for all
— but the hot-path, growing-N ones can ratchet the RSS high-water mark (see the
framework caveat). Ranked by OTS relevance:

- **`find_all_by_<field>` (multi-index)** — `multi_index_generators.rb:170` and
  `:433-434`. `index_set.members` (SMEMBERS whole bucket) + instantiate every
  match; **no `limit:`/pagination**; the instance-level branch also does an N+1
  load. Hot web path, N grows with the bucket. *The closest structural twin to
  #309, and the highest-severity Category-B site.*
- **`<collection>_with_permission`** — **issue #309**, `target_methods.rb:241`.
  See the focused section below.
- **`run_chores!`** — `housekeeping.rb:128`: `instances.to_a` (whole ZSET) then
  slice; the `limit:` is applied *after* materialization. Periodic/background;
  N = full instance count, grows over weeks.
- **Rebuild strategies (confirms F2)** — `rebuild_strategies.rb:108,226`;
  `multi_index_generators.rb:232,468`. `.members.each_slice(n)` fully materializes
  the identifier array *before* slicing, so `batch_size` bounds only the per-batch
  load, not the up-front fetch; the multi-index rebuilds additionally hold
  `cached_objects` = every hydrated object at once. Admin/rare path, so it cannot
  accumulate in a web worker; still a large transient spike.
- **Audit/health-check** — `management/audit.rb:286-287` etc.:
  `load_multi(scan_identifiers.to_a)` materializes *every deserialized instance of
  a class simultaneously* — the largest transient magnitude in the gem, but an
  admin/ops path.
- **List position scans** — `participant_methods.rb:325`, `participation.rb:724`:
  `collection.to_a.index(id)` (LRANGE 0 -1) to find one element; fix with `LPOS`.
- Reverse-index `participations.members` scans (`participation.rb:625,658,675`):
  small N (collections one object participates in); low severity.

The correct streaming primitives already exist and are the basis of the fixes:
`SortedSet#each`/`#scan` (ZSCAN, `sorted_set.rb:263-301,675`), `UnsortedSet#each`
(SSCAN), `HashKey#each`/`#hscan` (HSCAN), `ListKey#each` (LRANGE pagination),
`CollectionBase#each_record` (batched `load_multi`, `collection_base.rb:74-143`).

---

## Category C — Redis-side orphan accumulation

Real dataset-growth debt (OTS's expiring session/secret/token models will grow
these unboundedly in **Redis**), but `matches_ots_symptom = FALSE` for all — this
is server memory, not client process RSS. The structural root:

> **There is no keyspace-notification / expiry listener anywhere in `lib/`.** When
> Redis silently drops an object's hash at TTL, no Familia code runs. Every
> collection/index populated at `save` keeps the dead identifier. Removal happens
> **only** via explicit `destroy!` or the manual `repair_*`/`audit_*` tooling.

- **`{prefix}:instances` ZSET (confirms F1a)** — `horreum.rb:176`,
  `persistence.rb:708-741`. One permanent orphan per TTL-expired object; every
  model carries this set; `remove_from_instances!` is reachable only from
  `destroy!` (`persistence.rb:588`). The set is excluded from the TTL cascade
  because it is a `class_sorted_set` and the cascade iterates only instance-level
  `related_fields` (`expiration.rb:272-288` vs `related_fields.rb:208-216`). **High.**
- **class `unique_index` HASH + `objid_lookup` + `extid_lookup` (confirms F1b)** —
  `unique_index_generators.rb:93-99,428-484`; `object_identifier.rb:105`;
  `external_identifier.rb:24`. HSET on save vs HDEL only via `destroy!`; one orphan
  per expired object. OTS almost certainly uses `object_identifier`. **High.**
- **`multi_index` per-value SETs** — `multi_index_generators.rb:121-134`. Minted
  dynamically, never declared as related fields → never TTL'd, not deleted on
  scope `destroy!`, and **add-only on field-value change** (changing `role`
  admin→user leaves the id in *both* buckets). Four independent orphan vectors.
  **Medium-High.**
- **`atomic_swap` temp key (confirms F3)** — `atomic_operations.rb:32-35,54-84`.
  `build_temp_key` uses a **second-granularity** timestamp, so two rebuilds of the
  same index in the same second collide; on swap failure the temp key (a full
  index-sized HASH) is preserved with **no TTL** and never reaped. **Medium.**
- Instance-scoped unique index (whole-key TTL refreshed on every scope save while
  members orphan inside) and participation reverse-index orphans. **Medium / Low-Med.**

Related note: `run_chores!` iterates the same orphan-laden `instances` ZSET, so
chores waste work on phantom ids (`load_multi` returns nil) — a performance drag,
not a leak.

**Fix direction (all of Category C):** a reaper is the clean fix — either subscribe
to Redis keyspace `expired` notifications and prune the identifier from
`instances` + all indexes, or document `repair_*` as a required scheduled job for
expiring models and add a `*:rebuild:*` sweep + a TTL on temp keys.

---

## Category D — documentation and connection-lifecycle gaps

These do not explain the OTS process-RSS symptom, but they can create
operational pressure or lead applications into the Redis-side orphan pattern.

- **README `connection_provider` example recreates a pool per call** —
  `README.md:380-384` constructs a new `ConnectionPool` every time the provider
  runs, while `lib/familia/connection/handlers.rb:148` invokes the provider per
  connection request. The memoized form (`@pools[uri] ||= ConnectionPool.new(...)`)
  is already used in `docs/guides/index.md:94` and
  `docs/reference/api-technical.md:618`. This is connection churn and file-
  descriptor / `connected_clients` pressure—not a strict unbounded Ruby leak,
  because pools and sockets are GC-reclaimable. Update the README to match the
  memoized examples.
- **Expiration documentation omits the pruning constraint** —
  `lib/familia/features/expiration.rb:61-99` describes the cascade to
  per-instance relations but does not explain that class-level `instances` and
  `unique_index` entries cannot expire independently. Surface the existing
  `repair_instances!`, `audit_instances`, and `audit_indexes` maintenance tools
  for models that combine expiration with indexes.

---

## Issue #309 — focused diagnosis and fix design

> **Status: fixed.** Shipped on branch `fix/309-collection-with-permission-perf`,
> implementing the design below — additive `limit:`/`offset:`/`batch_size:`
> kwargs on the Array-returning method (internal `ZRANGEBYSCORE … LIMIT` paging)
> plus the ZSCAN-backed `each_<collection>_with_permission` enumerator.

**What it is.** The generated `<collection>_with_permission(min_permission)`
(`target_methods.rb:230-248`) issues one `ZRANGEBYSCORE key -inf +inf WITHSCORES`,
materializing the **entire** sorted set as a Ruby array of `[member, score]` pairs
(`raw_pairs`, `:241`), then filters per member in Ruby (`each_with_object`,
`:242-246`), deserializing survivors.

**Memory behaviour.** A per-call **transient O(N) spike**, not a retained leak. Peak
live memory ≈ O(N) for `raw_pairs` (outer array + N pair arrays + N member strings
+ N float scores) + O(M) for the kept survivors, plus O(N) short-lived churn from
`ScoreEncoding.permission?` → `decode_score` allocating a fresh Hash + Array per
member (`score_encoding.rb:140-151`). Nothing in Familia retains `raw_pairs` or the
result; both are GC-reclaimable at/after return. **So #309 does not itself match
the OTS symptom** — but it is a hot-path, growing-N site (Category B), so on a
large participation set it raises the RSS high-water mark.

**Why server-side filtering is impossible.** `encode_score` stores
`timestamp.to_i + permission_bits/1000.0` (`score_encoding.rb:129`); the permission
test is `permission_bits.anybits?(flag)` (`:168`) — a bitwise-AND membership test.
`ZRANGEBYSCORE` selects a single contiguous `[min,max]` interval, but "has the read
bit" ⇔ bits ∈ {1,3,5,…,255} (all odd) — 128 discrete, non-adjacent fractional
values, replicated across every integer timestamp. No single range expresses it
(the existing `permission_range`/`score_range` helpers, `:221-232`/`:255-279`, are
in fact semantically broken for this reason). The full fetch is by design; the
issue is bounding how much is pulled.

**Provenance.** This code entered on commit `ed69e69e` ("Fix dead/incorrect
participation permission query", already merged into 2.11.1), which replaced a
dead `zrangebyscore` call — a nonexistent method whose fallback also raised, so
the query raised unconditionally — with today's fetch-all-then-filter. The
author's own commit message reaches the same root cause independently: *"A
score-range query also cannot filter by permission: bits live in the fractional
part of the score and are not a contiguous range."* The O(N) fetch was therefore
a deliberate correctness fix, and #309 is the follow-on ask to bound it; its
regression tryout lives at `try/bug_fixes/permission_query_try.rb`.

**Fix design (bounded, backward-compatible).**

1. **Keep the default return an `Array`.** Callers rely on `.length`, indexing,
   `is_a?(Array)`, mutation, serialization. Switching the default to a lazy
   `Enumerator` is a breaking contract change.
2. **Add additive keyword args** `limit:`, `offset:`, `batch_size:` and stream
   internally via `ZRANGEBYSCORE … LIMIT offset count`, so peak intermediate memory
   is O(batch) and the result is O(limit):

   ```ruby
   target_class.define_method("#{collection_name}_with_permission") do
     |min_permission = :read, limit: nil, offset: 0, batch_size: 500|
     collection = send(collection_name)
     out = []; skipped = 0; page = 0
     loop do
       batch = collection.rangebyscoreraw('-inf', '+inf',
                 limit: [page * batch_size, batch_size], with_scores: true)
       break if batch.empty?
       batch.each do |raw_member, score|
         next unless ScoreEncoding.permission?(score, min_permission)
         if skipped < offset then skipped += 1; next end
         out << collection.deserialize_value(raw_member)
         return out if limit && out.size >= limit
       end
       break if batch.size < batch_size
       page += 1
     end
     out
   end
   ```

3. **Add an opt-in lazy sibling** `each_<collection>_with_permission(min_permission,
   batch_size:)` that yields survivors and `return to_enum(...) unless block_given?`,
   mirroring the repo's existing idiom (`SortedSet#each` `sorted_set.rb:263-267`;
   `CollectionBase#each_record` `collection_base.rb:74-75`). This gives O(1)-retained
   iteration with no full materialization.

**Trap to avoid — do NOT use score-cursor pagination here.** `encode_score` uses
`timestamp.to_i` (integer seconds, `score_encoding.rb:115`), so two members added in
the same second with the same permission bits have **identical** scores; an
exclusive `"(#{score}"` cursor bound would silently drop same-score members
straddling a page boundary. Use offset-based `LIMIT` (order-preserving, O(N²/batch)
CPU — acceptable for a memory fix) or ZSCAN (`collection.scan`, O(N) CPU but
unordered and may yield rare duplicates — document as the alternative, not the
default).

**Apply the same treatment to the twin** `find_all_by_<field>`
(`multi_index_generators.rb:170,433`): add `limit:`/pagination + a lazy `each_*`
variant, and drop the N+1 in the instance-level branch in favour of `load_multi`.

---

## Prioritised remediation

**Group 1 — fixes for the per-process (OTS) symptom.** Do these to close the
weeks-long RSS climb; each is small and low-risk.

1. **A1 encryption cache** *(highest expected impact for OTS; low effort)* — cap or
   re-key the request cache and gate population on an active `with_request_cache`
   frame. Risk: low (default path already unaffected). *This is the one most likely
   to actually stop the OTS climb.*
2. **A2 `reconnect!`** *(low effort)* — stop clearing the registration flags in
   `reconnect!`. Risk: low.
3. **A3 `@hooks`** *(low effort)* — add `off_*`/`clear_hooks!` and document
   boot-time registration. Risk: low.
4. **A4 `Familia.members`** *(low-med effort)* — `WeakMap` or skip anonymous
   classes. Risk: low; only relevant if OTS subclasses at runtime.

**Group 2 — scalability / Redis-footprint (not the process leak, but real).**

5. **#309 + `find_all_by_*`** *(med effort)* — bounded streaming + pagination as
   designed above. Impact: bounds hot-path spikes and result size.
6. **Category C reaper** *(med-high effort)* — keyspace-notification pruning or a
   scheduled `repair_*` + temp-key TTL + entropy in `build_temp_key`. Impact: stops
   unbounded **Redis** growth for expiring models. This is the biggest *Redis*
   sustainability win, independent of the process leak.
7. **`run_chores!` / rebuild `.members.each_slice`** *(low-med effort)* — switch to
   `each_record`/streaming so periodic/admin jobs don't materialise whole ZSETs.
   The class-level unique-index implementation plan is maintained in
   [Rebuild memory incident: class-level unique indexes](rebuild-memory-incident.md).
8. **Documentation and README pool example** *(low effort)* — document the
   expiration/index pruning constraint and memoize the advertised connection
   provider. This removes a misleading operational recommendation without
   changing runtime behaviour.

---

## How to confirm empirically

**In-gem (this branch, both proofs in `try/investigation/`):**
`bundle exec ruby try/investigation/process_memory_leak_proof.rb` reproduces
A1–A4 (pure Ruby, no Redis). `FAMILIA_TEST_URI=redis://127.0.0.1:6379 ruby
try/investigation/memory_leak_proof.rb` proves the Category C orphans (F1/F3) and
the Category B O(N) materialization high-water mark against a live Redis.

**In a running OTS process — determine which (if any) A-candidate is active:**

- **A1:** grep OTS for `with_request_cache` and for any direct assignment to
  `Fiber[:familia_request_cache_enabled]`. If caching is enabled outside a
  strictly per-request block (middleware `ensure`), that is the leak. Confirm by
  sampling `Fiber[:familia_request_cache]&.size` on a worker over time, or
  `ObjectSpace.each_object(String).count` trend after GC.
- **A2:** count OTS calls to `Familia.reconnect!` (startup only vs. failover/timer)
  with `enable_database_logging`/`enable_database_counter` on. Growing
  `RedisClient` middleware registrations confirm it.
- **A3:** grep for `Familia::Instrumentation.on_command`/`on_lifecycle`/`on_error`
  inside request or reload paths.
- **A4:** grep for `Class.new(Familia::Horreum)` / dynamic model definition; watch
  `Familia.members.size` over process life.

**General RSS-over-time signal (distinguishes leak from high-water plateau):**
sample per-worker `GC.stat(:heap_live_slots)`, `ObjectSpace.count_objects`, and RSS
on a fixed interval. A true Category-A leak shows `heap_live_slots` climbing
monotonically after `GC.start`; a Category-B high-water-mark plateau shows RSS
stepping up to a ceiling while live slots stay flat (fragmentation/arena
retention, not live-object growth). If neither climbs in-process while RSS does,
suspect native allocations outside Familia.

---

## Appendix — considered and dismissed (the discipline evidence)

The audit checked and cleared a large surface; the highlights that make the
"no default leak" conclusion credible:

- **No `@@` class variables in `lib/` at all.**
- **Class registries are bounded** — `@features_available`/`@feature_definitions`
  (`base.rb`), `@features_enabled` (`features.rb`), encryption `Registry.@providers`
  and `@managers` (keyed on ≤3 algorithms), `@registered_types` (`data_type.rb`),
  `SchemaRegistry.@schemas` (load-once), `Migration.migrations` (skips anonymous),
  `@min_length_for_bits_cache` (finite tiers), and every per-class definition map
  (`@fields`, `@field_types`, `@indexing_relationships`, …) — all keyed on
  load-time-finite sets.
- **Connection layer is clean** — `@connection_chain` is memoized (built once,
  rebuilt only on `reconnect!`/`connection_provider=`); the Fiber-local connection/
  transaction/pipeline slots are single-slot overwrite (one value per fiber,
  bounded by pool size) and cleared in `ensure`; the one uncleared slot
  (`Fiber[:familia_connection_handler_class]`, `handlers.rb:31`) holds a single
  already-permanent `Class` reference. No uri/thread-keyed client or pool cache
  exists.
- **All metaprogramming is one-time** — every `define_method`/`class_eval`/
  `const_set` fires at class-definition/load time behind the DSL or an `included`/
  `inherited` hook; there are zero `Class.new`/`Struct.new` in `lib/`.
- **Encryption is hardened** — `ObjectSpace` finalizers on ConcealedString/
  RedactedString use class-method procs (no `self` capture, so they do not pin);
  `derivation_count` is a single atomic, not a per-key hash; the record↔concealed
  cycle and `@dirty_fields` are per-instance/bounded and cleared on save.
- **`ThreadSafety::Monitor`** is disabled by default and, when on, keyed on
  fixed-literal section names with a `reset_metrics`; its `Thread.current.object_id`
  read is dead code.
- **`DatabaseLogger.@commands`** is a bounded ring buffer (10k), though
  `capture_enabled` defaults on and it retains command *values* — a footprint /
  data-retention note, not a leak (consider defaulting it off in production).
