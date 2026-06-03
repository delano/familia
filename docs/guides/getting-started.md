# Getting Started with Familia

This guide covers the core mental models you need to work effectively with Familia. If you're coming from ActiveRecord or another ORM, understanding these differences upfront will save debugging time.

## DataTypes: Live Proxies, Not Cached Relations

DataTypes (`list`, `set`, `zset`, `hashkey`) are *live proxies* to Redis keys, not cached relation objects. This is the most important conceptual difference from ActiveRecord.

| Aspect | ActiveRecord Relation | Familia DataType |
|--------|----------------------|------------------|
| Object identity | New object per query | Same object every call (memoized) |
| Data caching | Can memoize loaded records | No cache — every read hits Redis |
| Mutability | Mutable (chainable) | Frozen at creation |

```ruby
# ActiveRecord: new relation object each time, can cache results
User.where(active: true).object_id != User.where(active: true).object_id

# Familia: same frozen wrapper, always hits Redis
User.instances.object_id == User.instances.object_id  # true
User.instances.frozen?                                 # true
User.instances.to_a  # hits Redis now
User.instances.to_a  # hits Redis again
```

### Why This Matters

**Testing**: Class-level DataTypes (like `instances`) are frozen for thread safety. Attempting `define_singleton_method` on them raises `FrozenError`. To stub behavior in tests, stub the class method that returns the DataType, not the DataType instance itself:

```ruby
# Won't work — raises FrozenError
User.instances.define_singleton_method(:member?) { |_| true }

# Works — stub the class method
allow(User).to receive(:instances).and_return(mock_sorted_set)

# Or stub a method on the class that uses instances
allow(ApiConfig).to receive(:delete_for_domain!).and_return(true)
```

**Performance**: Since every read hits Redis, batch operations when possible:

```ruby
# Inefficient: N Redis calls
ids.each { |id| User.instances.member?(id) }

# Better: single pipeline
User.dbclient.pipelined do
  ids.each { |id| User.instances.member?(id) }
end
```

## Scalar Fields vs Collection Fields

Familia has a two-tier write model. Understanding when data hits Redis is critical.

**Scalar fields** (`field`) use deferred writes:
- Setters update in-memory only until `save` is called
- Fast writers (`field_name!`) write immediately

**Collection fields** (`list`, `set`, `zset`, `hashkey`) use immediate writes:
- Every mutating method executes the Redis command right away
- Cannot be rolled back if a subsequent operation fails

```ruby
# Safe pattern: scalars first, then collections
plan.name = "Premium"
plan.save

plan.features.clear      # immediate Redis DEL
plan.features.add("sso") # immediate Redis SADD

# Or use atomic_write for all-or-nothing
plan.atomic_write do
  plan.name = "Premium"
  plan.features.clear
  plan.features.add("sso")
end
```

See [Transaction Safety](../transaction_safety.md) for details.

## Next Steps

- [Field System](field-system.md) — field definitions and types
- [Feature System](feature-system.md) — modular capabilities
- [DataType Collections](datatype-collections.md) — working with lists, sets, and hashes
