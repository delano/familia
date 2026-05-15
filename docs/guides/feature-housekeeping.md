# Housekeeping Feature Guide

The Housekeeping feature provides a declarative DSL for registering named cleanup chores on Horreum models. It is designed for short-lived, repeated tidying against fields whose values have drifted over time -- not for versioned, one-shot migrations.

> [!TIP]
> Enable with `feature :housekeeping` and register cleanup blocks with `chore :name do |obj| ... end`. Run all of them with `obj.do_chores!` (aliased `tidy!`), or one with `obj.do_chore!(:name)`. Iteration and persistence are the caller's responsibility.

## Quick Start

```ruby
class Organization < Familia::Horreum
  feature :housekeeping

  field :planid

  chore :standardize_planid do |org|
    canonical = case org.planid
                when "pro", "Pro", "professional_v1" then "professional"
                when "free", "Free", "basic"         then "free"
                end
    if canonical && canonical != org.planid
      org.planid = canonical
      org.save
      true
    end
  end
end

org = Organization.from_identifier("acme-corp")
org.do_chores!
# => { standardize_planid: true }

# Or run a single chore by name (returns the block's raw value):
org.do_chore!(:standardize_planid)
# => true
```

## When to Use

| Tool | Use When |
|------|----------|
| `Familia::Migration::Base` | Versioned, one-shot transformation tracked across releases |
| `feature :housekeeping` | Short-lived chore run nightly until data is clean, then removed |
| Defensive code in setters | Permanent invariant enforced on every write |

Housekeeping fills the gap between migrations (heavy, tracked) and inline coercion (permanent). Register a chore, run it on a schedule for a few days, verify clean data, then delete the chore and the defensive code that handled the messy values.

## Core Capabilities

### Registration -- Class-Level DSL

Each chore is a named block bound to the model class:

```ruby
class User < Familia::Horreum
  feature :housekeeping

  field :email, :timezone

  chore :downcase_email do |user|
    next unless user.email && user.email != user.email.downcase
    user.email = user.email.downcase
    user.save
    true
  end

  chore :default_timezone do |user|
    next if user.timezone
    user.timezone = "UTC"
    user.save
    true
  end
end

User.chores.keys
# => [:downcase_email, :default_timezone]
```

### Execution -- Single Instance

Run all registered chores, or one by name:

```ruby
user = User.from_identifier("alice@example.com")

user.do_chores!
# => { downcase_email: true, default_timezone: nil }

user.tidy! # alias for do_chores!
# => { downcase_email: nil, default_timezone: nil }

user.do_chore!(:downcase_email)
# => true
```

`do_chores!` returns a hash mapping chore name to the block's return value. `do_chore!` returns the block's raw return value (not wrapped in a hash). A truthy result signals "modified"; `nil` or `false` signals "no-op". The feature does not interpret these values -- they are passed through for the caller's stats collection.

### Iteration -- Caller's Responsibility

The feature operates on a single instance. Bulk runs live in the consumer app:

```ruby
# nightly rake task
namespace :data do
  task tidy_orgs: :environment do
    stats = Hash.new(0)
    Organization.instances.each do |id|
      org = Organization.find_by_id(id) or next
      results = org.do_chores!
      results.each { |name, result| stats[name] += 1 if result }
    end
    puts stats.inspect
  end
end
```

The feature has no opinion about batching, SCAN vs KEYS, error aggregation, or scheduling -- the consumer app owns all of that.

## Generated Method Reference

### When a class declares `feature :housekeeping`

| Class | Method | Purpose |
|-------|--------|---------|
| **Class** | `chore(name, &block)` | Register a chore |
| | `chores` | Hash of registered chores |
| **Instance** | `do_chore!(name)` | Run a single chore by name; returns the block's raw value |
| | `do_chores!` | Run every registered chore; returns Hash |
| | `tidy!` | Alias for `do_chores!` |

## Design Constraints

1. **No implicit saves.** The block must call `save` (or `commit_fields`) itself. The feature does not auto-persist.
2. **No iteration.** Operates on a single instance. There is no class-level `tidy_all!`.
3. **No ordering.** Chores run in registration order, but should not depend on each other. If order matters, write one chore with sequential steps.
4. **Idempotent by convention.** Use the conditional pattern (`if canonical && canonical != org.planid`) so a second run is a no-op.
5. **Errors propagate.** The block can raise; the iteration code in the consumer app decides whether to rescue.

## Common Patterns

### Multiple Independent Chores

```ruby
class Customer < Familia::Horreum
  feature :housekeeping

  chore :trim_whitespace do |c|
    next unless c.name && c.name != c.name.strip
    c.name = c.name.strip
    c.save
    true
  end

  chore :uppercase_country do |c|
    next unless c.country && c.country != c.country.upcase
    c.country = c.country.upcase
    c.save
    true
  end
end

customer.do_chores!
# => { trim_whitespace: true, uppercase_country: nil }
```

### Sequential Steps in One Chore

When step B depends on step A's result, keep them in one block:

```ruby
chore :reconcile_billing do |account|
  changed = false
  if account.plan_id == "legacy"
    account.plan_id = "standard"
    changed = true
  end
  if account.plan_id == "standard" && account.billing_cycle.nil?
    account.billing_cycle = "monthly"
    changed = true
  end
  if changed
    account.save
    true
  end
end
```

### Tracking Modified Records

```ruby
modified = []
Organization.instances.each do |id|
  org = Organization.find_by_id(id) or next
  results = org.do_chores!
  modified << id if results.values.any?
end
puts "Modified #{modified.size} records: #{modified.inspect}"
```

### Error Aggregation

```ruby
errors = {}
Organization.instances.each do |id|
  org = Organization.find_by_id(id) or next
  begin
    org.do_chores!
  rescue => e
    errors[id] = e.message
  end
end
```

## Best Practices

1. **Keep chores short-lived.** Delete the registration once data is clean.
2. **Use `||=` and conditional checks** so a second run is a no-op.
3. **Save inside the block** -- the feature does not persist for you.
4. **Return truthy on modification, nil on no-op** so callers can collect stats.
5. **Prefer migrations for one-shot, versioned transformations.** Use housekeeping for ongoing tidying that can be run repeatedly.

## See Also

- [**Writing Migrations**](writing-migrations.md) - Versioned, one-shot data transformations
- [**Field System**](field-system.md) - How field values are stored and serialized
- [**Feature System**](feature-system.md) - How features are mixed into Horreum classes
