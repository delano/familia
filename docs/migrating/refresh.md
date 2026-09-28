# Migrating `refresh` and `refresh!` callers

`Horreum#refresh!`, `Horreum#refresh`, `HashKey#refresh!` and `HashKey#refresh` changed behavior in #443 and in the follow-up changes described below. Code that refreshes records it has just saved or loaded needs no change.

Check your code if it does any of the following:

- refreshes a record that may not be saved yet, or may have expired or been deleted
- expects a field to keep its in-memory value through `refresh!` when nothing is stored for it
- rescues `Redis::CommandError` around a `HashKey` refresh
- reads the return value of `HashKey#refresh!`
- relies on `HashKey#refresh!` to extend the key's TTL

## Breaking Changes

### `Horreum#refresh!` raises `Familia::KeyNotFoundError` for a missing key (#443)

The method was documented to raise `Familia::KeyNotFoundError` when the key does not exist, but it returned normally, kept the in-memory field values and cleared dirty tracking. It now raises, and the object is left as it was. `Horreum#refresh` behaves the same way.

```ruby
user = User.new(email: "alice@example.com")  # never saved

# Before: returned, and user.dirty? was false afterwards
# After: raises Familia::KeyNotFoundError
user.refresh!
```

When the record may not exist, load it instead. `find_by_id` and `load` return `nil` for a missing key:

```ruby
user = User.find_by_id("alice@example.com")
```

Or rescue the error where a missing record is expected:

```ruby
begin
  user.refresh!
rescue Familia::KeyNotFoundError
  # not saved yet, expired or deleted
end
```

Calling `exists?` first does not replace the rescue. The two calls are separate commands, and the key can expire or be deleted between them.

### `Horreum#refresh!` sets fields that are not stored to `nil`

Familia stores a `nil` field by leaving it out of the hash. `refresh!` assigned only the fields present in the stored hash, so a field with nothing stored kept whatever value the object held in memory, and dirty tracking was cleared anyway. It now sets every persistent field that is not stored to `nil`, which is what `load` and `find_by_id` give. The identifier field keeps its value. A Proc identifier, or an `identifier_field` that names a method rather than a field, has no identifier field: the fields it reads are set from the stored hash like any other field. `Horreum#refresh` behaves the same way.

This affects values set in memory and never saved, fields another writer removed, and defaults assigned by an `init` hook to an object built with `new`:

```ruby
class User < Familia::Horreum
  identifier_field :email
  field :email
  field :status

  def init
    @status ||= "active"
  end
end

user = User.new(email: "alice@example.com")  # init sets status to "active"
# The stored hash for alice@example.com has no status field.
user.refresh!

# Before: "active"
# After: nil, the same as User.load("alice@example.com").status
user.status
```

If code depends on a default surviving `refresh!`, apply the default where the value is read (`user.status || "active"`) or save it so that it is stored.

### `HashKey#refresh!` raises `Familia::KeyNotFoundError` instead of `Redis::CommandError` (#443)

For a missing hash, `HashKey#refresh!` and `HashKey#refresh` raised `Redis::CommandError` (`ERR wrong number of arguments for 'hmset' command`). They now raise `Familia::KeyNotFoundError`, which is also raised for a hash whose last field was removed. Update `rescue` clauses:

```ruby
# Before
begin
  user.settings.refresh!
rescue Redis::CommandError
  # ...
end

# After
begin
  user.settings.refresh!
rescue Familia::KeyNotFoundError
  # ...
end
```

### `HashKey#refresh!` and `HashKey#refresh` no longer write

A `HashKey` keeps no field values in memory, so there is nothing to reload. `refresh!` read the hash with `HGETALL`, then sent `HMSET` with the values it had just read and reset the key's expiration. It now sends only the `HGETALL`. Check the following.

**Return value.** `refresh!` returns the fields it read, as `hgetall` returns them. It used to return the `HMSET` reply, `"OK"`. `refresh` still returns the `HashKey` itself.

```ruby
user.settings.refresh!  # Before: "OK"
                        # After:  {"theme" => "dark", "lang" => "en"}
```

**Expiration.** The old `refresh!` called `update_expiration`, which sends `EXPIRE` with the default expiration when one is configured. The Valkey `EXPIRE` documentation (<https://valkey.io/commands/expire/>) says: "It is possible to call `EXPIRE` using as argument a key that already has an existing expire set. In this case the time to live of a key is *updated* to the new value." A refresh therefore extended the TTL. It no longer does. If you relied on that, extend it explicitly:

```ruby
user.settings.refresh!
user.settings.update_expiration
```

**Writes by other clients.** The Valkey `HMSET` documentation (<https://valkey.io/commands/hmset/>) says: "This command overwrites any specified fields already existing in the hash." The old `refresh!` sent every field it had read, so a value another client wrote between the `HGETALL` and the `HMSET` was replaced by the value read before it. The old `refresh!` also serialized each value again before writing it, so a value stored without JSON encoding (for example `not-json` written with `redis-cli HSET`) was stored back as the JSON string `"not-json"`. Both writes are gone, and no change is needed on your side.

**Dirty-write check.** The old `refresh!` ran the check that collection writes run when the parent has unsaved field changes. It warned, or raised `Familia::Problem` under `dirty_write_warnings :strict`, with `Familia.strict_write_order`, or when the parent had never been saved. It no longer runs the check. Writes through the same `HashKey` still do.

## Other changes

No action is needed for these.

### Refreshing inside a transaction or pipeline raises `Familia::OperationModeError`

All four methods need the `HGETALL` reply, which is a `Redis::Future` inside `transaction`, `pipelined` or `atomic_write`. Such code already failed: the methods raised `NoMethodError` on the `Redis::Future`. They now raise `Familia::OperationModeError` before sending anything, and the message says to refresh before opening the block:

```ruby
# Before: NoMethodError. After: Familia::OperationModeError
user.atomic_write do
  user.refresh!
  user.name = "Alice"
end

# Instead
user.refresh!
user.atomic_write do
  user.name = "Alice"
end
```

### `Horreum#refresh!` no longer removes lookup entries

`Horreum#refresh!` no longer sends `HDEL` to the `objid_lookup` or `extid_lookup` hash. The `objid` and `extid` setters (`lib/familia/features/object_identifier.rb` and `lib/familia/features/external_identifier.rb`) remove the lookup entry of the value they replace when the new value differs, and `refresh!` used to call them with the in-memory value still in place. On an object built from another record's attributes, that removed the other record's lookup entry. `refresh!` now sends only `HGETALL`.

### A failed `Horreum#refresh!` leaves the object as it was

If a field setter raises while `refresh!` assigns the stored values, `refresh!` now puts the object back as it was before re-raising: field values, transient fields and dirty tracking. An example is `Familia::EncryptionError` for an encrypted field whose stored envelope names an algorithm that is not available. It used to leave the fields before the failing one assigned, transient fields reset, and the assigned fields marked dirty.
