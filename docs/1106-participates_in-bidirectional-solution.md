# Bidirectional Relationships in Familia

> **Document Status**: Updated 2025-12 to reflect current implementation including
> `:through` option and `config_name`-based method naming.

## The Original Naming Problem

`bidirectional: true` was misleading because:

1. It's not truly bidirectional - It only helps you manage membership in specific instances, not query all memberships
2. Better name would be: `generate_participant_methods: true`
3. True bidirectionality would mean both sides can easily query their relationships

## What True Bidirectionality Should Look Like

### Option 1: Auto-generate reverse collections

```ruby
class Customer < Familia::Horreum
  participates_in Team, :members, bidirectional: true, reverse: :teams
end

# Should generate:
customer.teams           # All teams this customer is in
customer.teams.count     # How many teams
customer.teams.include?(team_id)  # Check membership
```

### Option 2: Make bidirectional actually bidirectional

```ruby
class Customer < Familia::Horreum
  participates_in Team, :members, bidirectional: true
end

# Should auto-generate (using pluralized class name):
customer.teams           # Since we're participating in Team class
customer.organizations   # If also participating in Organization class
```

## The Implementation Gap (Historical Context)

Looking at the original usage pattern:

```ruby
# Easy to go from Team → Customers
team.members.to_a        # Simple!
customers = Customer.multiget(*team.members.to_a)

# Hard to go from Customer → Teams
customer.participations.members
  .select { |k| k.start_with?("team:") }
  .map { |k| k.split(':')[1] }
  # ... etc - complicated!
```

### What Was Really Happening

The bidirectional flag only controlled whether these instance-to-instance methods were generated:
- `customer.add_to_team_members(specific_team)`
- `customer.in_team_members?(specific_team)`

It did NOT create instance-to-collection methods:
- `customer.teams` ❌
- `customer.all_team_memberships` ❌

---

## Current Implementation (Familia 2.x)

The solution now auto-generates reverse collection methods on participant classes.

### Implemented API (Using `_instance` Suffix + `config_name` Naming)

**Important**: Method names are based on the target class's `config_name` (snake_case of
the full class name), not just the class basename. This ensures uniqueness when
multiple classes have the same basename (e.g., `Admin::Team` vs `Public::Team`).

```ruby
class Domain < Familia::Horreum
  # Customer.config_name => "customer"
  participates_in Customer, :domains
  # Auto-generates on Domain:
  #   domain.customer_instances
  #   domain.customer_ids
  #   domain.customer?
  #   domain.customer_count

  # With custom naming via `as:`
  participates_in Customer, :partner_domains, as: :partners
  # Auto-generates:
  #   domain.partners_instances
  #   domain.partners_ids
  #   domain.partners?
  #   domain.partners_count
end

class ProjectTeam < Familia::Horreum
  # Note: config_name is "project_team", not "team"
end

class User < Familia::Horreum
  participates_in ProjectTeam, :members
  # Auto-generates: user.project_team_instances (NOT user.team_instances)
end
```

### Forward Direction (Target Class Methods)

```ruby
customer.domains                         # → SortedSet of domain IDs
customer.add_domains_instance(domain)    # → Adds + tracks participation
customer.remove_domains_instance(domain) # → Removes + untracks
```

### Reverse Direction (Participant Class Methods)

```ruby
domain.customer_instances    # → Array of Customer instances
domain.customer_ids          # → Array of customer IDs (no object loading)
domain.customer?             # → Boolean: participates in any customers?
domain.customer_count        # → Integer count without loading objects
```

### Implementation Status

| Method Pattern | Forward (Target) | Reverse (Participant) |
|----------------|------------------|----------------------|
| `*_instances` | `add_*_instance`, `remove_*_instance` | `{config_name}_instances` |
| `*_ids` | N/A (use collection directly) | `{config_name}_ids` |
| `*?` | N/A | `{config_name}?` |
| `*_count` | N/A (use `collection.size`) | `{config_name}_count` |

---

## Through Models (New in 2.x)

The `:through` option enables rich join model patterns for storing additional
membership data (roles, timestamps, status).

```ruby
class OrganizationMembership < Familia::Horreum
  feature :object_identifier  # Required for through models
  prefix :org_membership

  field :organization_id
  field :customer_id
  field :role             # 'owner', 'admin', 'member'
  field :status           # 'active', 'pending', 'declined'
  field :invited_at
  field :joined_at
end

class Customer < Familia::Horreum
  participates_in Organization, :members,
    score: :joined,
    through: :OrganizationMembership
end
```

### Through Model Behavior

```ruby
# Adding creates/updates the through model
membership = org.add_members_instance(customer, through_attrs: { role: 'admin' })
membership.role  # => 'admin'

# Chaining pattern also works
membership = org.add_members_instance(customer)
membership.role = 'admin'
membership.save

# Removing destroys the through model
org.remove_members_instance(customer)  # OrganizationMembership is deleted
```

### Through Model Requirements

- Must have `feature :object_identifier` enabled
- Through model is auto-created on add, auto-destroyed on remove
- Attributes can be passed inline via `through_attrs:` or set after

---

## Naming Rationale: Why `_instance` Suffix?

The implementation uses an `_instance` suffix pattern instead of pluralization/singularization:

**Target Methods (Forward Direction):**
- `customer.add_domains_instance(domain)` instead of `customer.add_domain(domain)`
- `customer.remove_domains_instance(domain)` instead of `customer.remove_domain(domain)`

**Reverse Collection Methods:**
- `domain.customer_instances` instead of `domain.customers`
- `user.organization_instances` instead of `user.organizations`

**Benefits:**
1. **No irregular plurals** - Avoids issues with "person/people", "child/children", "foot/feet"
2. **Clear intent** - The suffix makes it obvious you're working with instances, not counts or IDs
3. **Consistent pattern** - Same suffix for both forward and reverse operations
4. **No external dependencies** - No need for inflection libraries like `dry-inflector`
5. **Predictable** - Easy to remember and document

**Trade-off:**
- Slightly more verbose, but eliminates an entire class of edge case bugs

---

## Future Consideration: `method_prefix:` Option

The current implementation uses `config_name` which can be verbose for namespaced
classes (e.g., `admin_project_team_instances`). A future enhancement could add
explicit control:

```ruby
# Potential future API (not yet implemented)
participates_in Admin::ProjectTeam, :members, method_prefix: :team
# Would generate: user.team_instances instead of user.admin_project_team_instances
```

This would give developers explicit control over method naming while maintaining
the predictability of the current system.

---

## Key Requirements (All Implemented)

1. **Automatic generation** - No manual method definitions needed ✓
2. **Multiple collections** - Union of all collections to same target class ✓
3. **Performance** - Efficient ID-only access without loading objects ✓
4. **Custom naming** - Override auto-generated names via `as:` parameter ✓
5. **Thread-safe** - No caching means no stale data or cache invalidation complexity ✓
6. **Through models** - Rich join data via `:through` option ✓

## Benefits

- **Symmetry** - Both directions equally convenient
- **Discoverability** - Natural Ruby method names
- **Efficiency** - Choose between full objects, IDs, or counts
- **Backwards compatible** - All existing code continues to work
- **Extensible** - Through models enable rich membership data
