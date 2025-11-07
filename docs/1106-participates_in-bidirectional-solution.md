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

API

class User < Familia::Horreum
  participates_in Team, :members          # Auto-generates: user.teams
  participates_in Team, :admins           # Also adds to: user.teams (union)
  participates_in Organization, :employees
  participates_in Organization, :contractors, reverse: :contracting_orgs
end

# Forward (existing)
team.members                    # → SortedSet of user IDs
team.add_member(user)           # → Adds to collection + tracks participation

# Reverse (NEW)
user.teams                      # → Array of Team instances user belongs to
user.team_ids                   # → Array of team IDs (efficient, no loading)
user.teams?                     # → Boolean: belongs to any teams?
user.teams_count                # → Count without loading objects

# Custom naming
user.contracting_orgs           # → Custom name via reverse: parameter

Key Requirements

1. Automatic generation - No manual method definitions needed
2. Multiple collections - Union of all collections to same target class
3. Performance - Efficient ID-only access without loading objects
4. Custom naming - Override auto-generated names when needed
5. Thread-safe - Proper memoization and caching

Benefits

- Symmetry - Both directions equally convenient
- Discoverability - Natural Ruby method names
- Efficiency - Choose between full objects, IDs, or counts
- Backwards compatible - All existing code continues to work
