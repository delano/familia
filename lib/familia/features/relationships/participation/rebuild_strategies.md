## Indexes vs. Participations: Critical Distinction

**Indexes are derived data** - they can be rebuilt from source:
```ruby
# Indexes derive from object fields and can be reconstructed
User.rebuild_email_lookup  # Rebuilds from all User instances
```

**Participations are primary data** - they represent business decisions:
```ruby
# Participations are intentional relationships that must be explicitly created
@team.add_members_instance(@user)  # Human/business decision about team membership
```

**Why this matters for rebuilding:**

| Aspect | Indexes | Participations |
|--------|---------|----------------|
| **Source of truth** | Object field values | Business logic/user actions |
| **Can rebuild?** | ✅ Yes - iterate instances | ❌ No - requires domain knowledge |
| **Fix when wrong** | Run rebuild method | Re-apply business logic |
| **Nature** | Computed/derived | Intentional/chosen |

**Examples:**

```ruby
# ✅ INDEXES - Can rebuild because source exists
User.rebuild_email_lookup      # Rebuilds from User.email field values
company.rebuild_badge_index    # Rebuilds from Employee.badge_number values

# ❌ PARTICIPATIONS - Cannot rebuild without knowing intent
@team.members                  # Which users should be members? (business decision)
@org.employees                 # Who works here? (HR/business logic)
@project.contributors          # Who contributed? (tracked externally)

# To fix participation data, reapply the business logic:
correct_members.each { |user| @team.add_members_instance(user) }
```

**When indexes fail**, run the rebuild method.
**When participations are wrong**, understand why they're wrong and reapply your application's business rules.
