The Naming Problem

bidirectional: true is misleading because:

1. It's not truly bidirectional - It only helps you manage membership in specific instances, not query all memberships
2. Better name would be: generate_participant_methods: true
3. True bidirectionality would mean both sides can easily query their relationships

What True Bidirectionality Should Look Like

Option 1: Auto-generate reverse collections

class Customer < Familia::Horreum
  participates_in Team, :members, bidirectional: true, reverse: :teams
end

# Should generate:
customer.teams           # All teams this customer is in
customer.teams.count     # How many teams
customer.teams.include?(team_id)  # Check membership

Option 2: Make bidirectional actually bidirectional

class Customer < Familia::Horreum
  participates_in Team, :members, bidirectional: true
end

# Should auto-generate (using pluralized class name):
customer.teams           # Since we're participating in Team class
customer.organizations   # If also participating in Organization class

Current Implementation Gap

Looking at the actual usage pattern:
# Easy to go from Team → Customers
team.members.to_a        # Simple!
customers = Customer.multiget(*team.members.to_a)

# Hard to go from Customer → Teams
customer.participations.members
  .select { |k| k.start_with?("team:") }
  .map { |k| k.split(':')[1] }
  # ... etc - complicated!

What's Really Happening

The bidirectional flag only controls whether these instance-to-instance methods are generated:
- customer.add_to_team_members(specific_team)
- customer.in_team_members?(specific_team)

It does NOT create instance-to-collection methods:
- customer.teams ❌
- customer.all_team_memberships ❌


The functionality we are hoping to achieve:
Bidirectional Relationships Feature Spec

Problem

Currently, Familia relationships are asymmetric. While you can easily query team.members to get all members, there's no convenient way to get
all teams a user belongs to without manually parsing the participations reverse index.

Solution

Auto-generate reverse collection methods on participant classes to provide symmetric access to relationships.

## Implemented API (Using _instance Suffix Pattern)

class User < Familia::Horreum
  participates_in Team, :members          # Auto-generates: user.team_instances
  participates_in Team, :admins           # Also adds to: user.team_instances (union)
  participates_in Organization, :employees # Auto-generates: user.organization_instances
  participates_in Organization, :contractors, as: :contracting_orgs  # Custom name
end

# Forward (existing)
team.members                       # → SortedSet of user IDs
team.add_members_instance(user)    # → Adds to collection + tracks participation
team.remove_members_instance(user) # → Removes from collection + untracks

# Reverse (NEW)
user.team_instances                # → Array of Team instances user belongs to
user.team_ids                      # → Array of team IDs (efficient, no loading)
user.team?                         # → Boolean: belongs to any teams?
user.team_count                    # → Count without loading objects

# Custom naming (user chooses base name via as: parameter)
user.contracting_orgs_instances    # → Array of Organization instances
user.contracting_orgs_ids          # → Array of IDs
user.contracting_orgs?             # → Boolean
user.contracting_orgs_count        # → Count

## Naming Rationale: Why `_instance` Suffix?

The implementation uses an `_instance` suffix pattern instead of pluralization/singularization to avoid fragility:

**Target Methods (Forward Direction):**
- `team.add_members_instance(user)` instead of `team.add_member(user)`
- `team.remove_members_instance(user)` instead of `team.remove_member(user)`

**Reverse Collection Methods:**
- `user.team_instances` instead of `user.teams`
- `user.organization_instances` instead of `user.organizations`

**Benefits:**
1. **No irregular plurals** - Avoids issues with words like "person/people", "child/children", "foot/feet"
2. **Clear intent** - The suffix makes it obvious you're working with instances, not counts or IDs
3. **Consistent pattern** - Same suffix for both forward and reverse operations
4. **No external dependencies** - Removes need for inflection libraries like `dry-inflector`
5. **Predictable** - Easy to remember and document

**Trade-off:**
- Slightly more verbose, but eliminates an entire class of edge case bugs

Key Requirements

1. Automatic generation - No manual method definitions needed
2. Multiple collections - Union of all collections to same target class
3. Performance - Efficient ID-only access without loading objects (no caching for data freshness)
4. Custom naming - Override auto-generated names when needed via `as:` parameter
5. Thread-safe - No caching means no stale data or cache invalidation complexity

Benefits

- Symmetry - Both directions equally convenient
- Discoverability - Natural Ruby method names
- Efficiency - Choose between full objects, IDs, or counts
- Backwards compatible - All existing code continues to work
