# try/features/relationships/participation_bidirectional_try.rb

require_relative '../../../lib/familia'

# Test demonstrating true bidirectional participation functionality
# This shows the improvement from asymmetric to symmetric relationship access

# Setup test classes
class ProjectTeam < Familia::Horreum
  feature :relationships

  identifier_field :team_id
  field :team_id
  field :name
  field :department

  def init
    @team_id ||= "team_#{SecureRandom.hex(4)}"
  end
end

class ProjectOrganization < Familia::Horreum
  feature :relationships

  identifier_field :org_id
  field :org_id
  field :name
  field :type

  def init
    @org_id ||= "org_#{SecureRandom.hex(4)}"
  end
end

class ProjectUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :name
  field :role

  # Define bidirectional participation relationships
  # These will auto-generate reverse collection methods with _instances suffix
  participates_in ProjectTeam, :members          # Generates: user.project_team_instances
  participates_in ProjectTeam, :admins           # Also adds to user.project_team_instances (union)
  participates_in ProjectOrganization, :employees # Generates: user.project_organization_instances

  # Custom reverse method name (user chooses the base name)
  participates_in ProjectOrganization, :contractors, as: :contracting_orgs

  def init
    @user_id ||= "user_#{SecureRandom.hex(4)}"
  end
end

# Create test data
@user1 = ProjectUser.new(email: 'alice@example.com', name: 'Alice', role: 'developer')
@user2 = ProjectUser.new(email: 'bob@example.com', name: 'Bob', role: 'manager')

@team1 = ProjectTeam.new(name: 'Frontend Team', department: 'Engineering')
@team2 = ProjectTeam.new(name: 'Backend Team', department: 'Engineering')
@team3 = ProjectTeam.new(name: 'Design Team', department: 'Product')

@org1 = ProjectOrganization.new(name: 'TechCorp Inc', type: 'employer')
@org2 = ProjectOrganization.new(name: 'FreelanceCorp', type: 'contractor')

# Save all objects
[@user1, @user2, @team1, @team2, @team3, @org1, @org2].each(&:save)

# Set up relationships using forward direction (existing functionality)
@team1.members.add(@user1.identifier)
@team2.members.add(@user1.identifier)
@team1.admins.add(@user1.identifier)
@org1.employees.add(@user1.identifier)
@org2.contractors.add(@user1.identifier)

@team3.members.add(@user2.identifier)
@org1.employees.add(@user2.identifier)

# Track participations in reverse index using proper string keys
@user1.track_participation_in("project_team:#{@team1.identifier}:members")
@user1.track_participation_in("project_team:#{@team2.identifier}:members")
@user1.track_participation_in("project_team:#{@team1.identifier}:admins")
@user1.track_participation_in("project_organization:#{@org1.identifier}:employees")
@user1.track_participation_in("project_organization:#{@org2.identifier}:contractors")

# Set up user2 in fewer relationships
@team3.members.add(@user2.identifier)
@org1.employees.add(@user2.identifier)
@user2.track_participation_in("project_team:#{@team3.identifier}:members")
@user2.track_participation_in("project_organization:#{@org1.identifier}:employees")

## Test the OLD way - difficult and verbose
# Before: Getting teams for a user required manual parsing
old_way_keys = @user1.participations.members.select { |k| k.start_with?("project_team:") && k.end_with?(":members") }
old_way_ids = old_way_keys.map { |k| k.split(':')[1] }.uniq
old_way_teams = ProjectTeam.load_multi(old_way_ids).compact
old_way_teams.map(&:name).sort
#=> ["Backend Team", "Frontend Team"]

## Debug - Check if methods are defined
@user1.respond_to?(:project_team_instances)
#=> true

## Debug - Check participations data
@user1.participations.members
#=> ["project_team:#{@team1.identifier}:members", "project_team:#{@team2.identifier}:members", "project_team:#{@team1.identifier}:admins", "project_organization:#{@org1.identifier}:employees", "project_organization:#{@org2.identifier}:contractors"]

## Debug - Check if participating_ids_for_target works
ids = @user1.participating_ids_for_target(ProjectTeam)
ids
#=> [@team1.identifier, @team2.identifier]

## Debug - Test individual team loading
ProjectTeam.load(@team1.identifier).name
#=> "Frontend Team"

## Debug - Test load_multi with actual IDs
test_ids = [@team1.identifier, @team2.identifier]
ProjectTeam.load_multi(test_ids).compact.map(&:name).sort
#=> ["Backend Team", "Frontend Team"]

## Debug - Check what project_teams method returns
result = @user1.project_team_instances
puts "project_teams method returns: #{result.inspect}"
result.map(&:name).sort
#=> ["Backend Team", "Frontend Team"]

## Test NEW way - clean and intuitive reverse collection method
user_teams = @user1.project_team_instances  # Auto-generated pluralized from ProjectTeam class name
user_teams.map(&:name).sort
#=> ["Backend Team", "Frontend Team"]

## Test that both users and admins collections are included (union behavior)
all_team_participations = @user1.project_team_instances  # Should include both members and admins
all_team_participations.map(&:name).sort
#=> ["Backend Team", "Frontend Team"]

## Test IDs-only method (efficient, no object loading)
user_team_ids = @user1.project_team_ids
user_team_ids.sort
#=> [@team1.identifier, @team2.identifier].sort

## Test boolean check method
@user1.project_team?
#=> true

## Test count method returns correct number
@user1.project_team_count
#=> 2

## Test organizations (different target class)
user_orgs = @user1.project_organization_instances
user_orgs.map(&:name).sort
#=> ["FreelanceCorp", "TechCorp Inc"]

## Test custom reverse method name
contracting_orgs_instances = @user1.contracting_orgs_instances
contracting_orgs_instances.map(&:name)
#=> ["FreelanceCorp"]

## Test user with fewer relationships
@user2.project_team_instances.map(&:name)
#=> ["Design Team"]

## Test user2 count
@user2.project_team_count
#=> 1

## Test user2 organizations
@user2.project_organization_instances.map(&:name)
#=> ["TechCorp Inc"]

## Test create empty user with no memberships
@user3 = ProjectUser.new(email: 'charlie@example.com', name: 'Charlie')
@user3.save
@user3.project_team_instances
#=> []

## Test empty user with IDs, check and count
@user3.project_team_ids
#=> []

## Test empty user boolean check
@user3.project_team?
#=> false

## Test empty user count
@user3.project_team_count
#=> 0

## Test that forward direction still works (backwards compatibility)
@team1.members.to_a.sort
#=> [@user1.identifier]

## Test admin collection forward direction
@team1.admins.to_a
#=> [@user1.identifier]

## Test bidirectional consistency - forward direction
team1_member_ids = @team1.members.to_a
team1_members = ProjectUser.load_multi(team1_member_ids).compact
team1_members.map(&:name)
#=> ["Alice"]

## Test bidirectional consistency - reverse direction
user1_teams = @user1.project_team_instances
user1_team_ids = user1_teams.map(&:identifier)
user1_team_ids.include?(@team1.identifier)
#=> true

## Test multiple users in same team
@team1.add_member(@user2)

## Test team1 now has two members
team1_all_members = @team1.members.to_a.sort
#=> [@user1.identifier, @user2.identifier].sort

## Test both users show up in team1 - user1
@user1.project_team_instances.map(&:name).include?("Frontend Team")
#=> true

## Test both users show up in team1 - user2
@user2.project_team_instances.map(&:name).include?("Frontend Team")
#=> true

## Test cleanup - remove relationships
@user1.untrack_participation_in("project_team:#{@team1.identifier}:members")

## Test cache invalidation on removal
@user1.instance_variable_set(:@reverse_collections_cache, nil)
updated_teams = @user1.project_team_instances.map(&:name).sort
updated_teams.include?("Frontend Team")
#=> false

## Test still admin of team1 after member removal
@user1.project_team_instances.map(&:name).include?("Frontend Team")
#=> true
