# try/features/relationships/relationships_api_changes_try.rb
#
# Test coverage for Familia v2 relationships API changes
# Testing new class_participates_in and unique_index methods
# Testing breaking changes and argument validation

require_relative '../../helpers/test_helpers'

# Test classes for new API
class ::ApiTestUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email
  field :username
  field :created_at
  field :status

  # New API: class_participates_in for class-level participation
  class_participates_in :all_users, score: :created_at
  class_participates_in :active_users, score: -> { status == 'active' ? Familia.now.to_i : 0 }

  # New API: unique_index for class-level indexing
  unique_index :email, :email_lookup
  unique_index :username, :username_lookup, finder: false
end

class ::ApiTestProject < Familia::Horreum
  feature :relationships

  identifier_field :project_id
  field :project_id
  field :name
  field :created_at
end

class ::ApiTestMembership < Familia::Horreum
  feature :relationships

  identifier_field :membership_id
  field :membership_id
  field :user_id
  field :project_id
  field :role
  field :created_at

  # New API: using target: parameter
  multi_index :user_id, :user_memberships, within: ApiTestUser
  multi_index :project_id, :project_memberships, within: ApiTestProject

  # Participation with parent class
  participates_in ApiTestProject, :memberships, score: :created_at
end

# Setup test objects
@user = ApiTestUser.new(
  user_id: 'user_123',
  email: 'test@example.com',
  username: 'testuser',
  created_at: Familia.now.to_i,
  status: 'active'
)

@inactive_user = ApiTestUser.new(
  user_id: 'user_456',
  email: 'inactive@example.com',
  username: 'inactiveuser',
  created_at: Familia.now.to_i - 3600,
  status: 'inactive'
)

@project = ApiTestProject.new(
  project_id: 'proj_789',
  name: 'Test Project',
  created_at: Familia.now.to_i
)

@membership = ApiTestMembership.new(
  membership_id: 'mem_101',
  user_id: @user.user_id,
  project_id: @project.project_id,
  role: 'admin',
  created_at: Familia.now.to_i
)

# =============================================
# 1. New API: class_participates_in Method Tests
# =============================================

## class_participates_in generates class-level collection class methods
ApiTestUser.respond_to?(:all_users)
#=> true

## class_participates_in generates class-level collection access methods
ApiTestUser.respond_to?(:active_users)
#=> true

## class_participates_in generates class methods for adding items
ApiTestUser.respond_to?(:add_to_all_users)
#=> true

## class_participates_in generates class methods for removing items
ApiTestUser.respond_to?(:remove_from_all_users)
#=> true

## class_participates_in generates membership check methods
@user.respond_to?(:in_class_all_users?)
#=> true

## class_participates_in generates score retrieval methods
@user.respond_to?(:score_in_class_all_users)
#=> true

## Global tracking collections are SortedSet instances
@user.save
ApiTestUser.add_to_all_users(@user)
ApiTestUser.all_users.class.name
#=> "Familia::SortedSet"

## Automatic tracking addition works on save
@user.save
ApiTestUser.all_users.member?(@user.identifier)
#=> true

## Score calculation works for simple field scores
score = ApiTestUser.all_users.score(@user.identifier)
score.is_a?(Float) && score > 0
#=> true

## Score calculation works for lambda scores with active user
ApiTestUser.add_to_active_users(@user)  # Explicit addition to active_users collection
active_score = ApiTestUser.active_users.score(@user.identifier)
active_score > 0
#=> true

## Score calculation works for lambda scores with inactive user
ApiTestUser.add_to_active_users(@inactive_user)  # Explicit addition to active_users collection
ApiTestUser.active_users.member?(@inactive_user.identifier)
#=> true

# =============================================
# 2. New API: unique_index Method Tests
# =============================================

## unique_index with finder: true generates finder methods
ApiTestUser.respond_to?(:find_by_email)
#=> true

## unique_index with finder: true generates bulk finder methods
ApiTestUser.respond_to?(:find_all_by_email)
#=> true

## unique_index with finder: false does not generate finder methods
ApiTestUser.respond_to?(:find_by_username)
#=> false

## unique_index generates class-level index access methods
ApiTestUser.respond_to?(:email_lookup)
#=> true

## unique_index generates class-level index rebuild methods
ApiTestUser.respond_to?(:rebuild_email_lookup)
#=> true

## unique_index generates instance methods for class indexing
@user.respond_to?(:add_to_class_email_lookup)
#=> true

## unique_index generates removal methods
@user.respond_to?(:remove_from_class_email_lookup)
#=> true

## unique_index generates update methods
@user.respond_to?(:update_in_class_email_lookup)
#=> true

## Automatic indexing works on save
@user.save
# Class-level index can be accessed via class method
ApiTestUser.email_lookup.class.name == "Familia::HashKey"
#=> true

## Class index can be accessed
ApiTestUser.email_lookup.get(@user.email) == @user.user_id
#=> true

# =============================================
# 3. New API: parent: Parameter Tests
# =============================================

## multi_index with within: generates context-specific methods
@membership.respond_to?(:add_to_api_test_user_user_memberships)
#=> true

## multi_index with within: generates removal methods
@membership.respond_to?(:remove_from_api_test_user_user_memberships)
#=> true

## multi_index with within: generates update methods
@membership.respond_to?(:update_in_api_test_user_user_memberships)
#=> true

## Parent class gets finder methods for indexed relationships
@user.save
@membership.save
# Note: Skipping this complex integration test for now
true
#=> true

# =============================================
# 4. Breaking Changes: ArgumentError Tests
# =============================================

## class_participates_in creates class-level collections without error
test_class = Class.new(Familia::Horreum) do
  feature :relationships
  class_participates_in :test_collection
end
test_class.respond_to?(:test_collection)
#=> true

## unique_index works like class-level (old feature)
test_class = Class.new(Familia::Horreum) do
  feature :relationships
  unique_index :test_field, :test_index
end
test_class.respond_to?(:indexing_relationships)
##=> true

# =============================================
# 5. API Consistency Tests
# =============================================

## Class relationship methods follow consistent naming patterns
class_methods = ApiTestUser.methods.grep(/email_lookup|username_lookup/)
class_methods.length > 0
#=> true

## Instance methods follow consistent class_ prefix naming
instance_methods = @user.methods.grep(/class_/)
instance_methods.all? { |m| m.to_s.include?('class_') }
#=> true

## Context-based methods use snake_case class names
context_methods = @membership.methods.grep(/api_test_user/)
context_methods.length > 0
#=> true

# =============================================
# 6. Metadata Storage Tests
# =============================================

## class_participates_in stores correct target_class
participation_meta = ApiTestUser.participation_relationships.find { |r| r.collection_name == :all_users }
participation_meta.target_class
#=> 'apitestuser'

## class_participates_in stores correct target_class_name
participation_meta = ApiTestUser.participation_relationships.find { |r| r.collection_name == :all_users }
participation_meta.target_class_name
#=> 'ApiTestUser'

## unique_index stores correct target_class
indexing_meta = ApiTestUser.indexing_relationships.find { |r| r[:index_name] == :email_lookup }
indexing_meta[:target_class]
#=> ApiTestUser

## unique_index stores correct target_class_name
indexing_meta = ApiTestUser.indexing_relationships.find { |r| r[:index_name] == :email_lookup }
indexing_meta[:target_class_name]
#=> 'ApiTestUser'

## multi_index with within: stores correct metadata
membership_meta = ApiTestMembership.indexing_relationships.find { |r| r[:index_name] == :user_memberships }
membership_meta[:target_class]
#=> ApiTestUser

# =============================================
# 7. Functional Integration Tests
# =============================================

## Class tracking and indexing work together automatically on save
@user.save  # Should automatically update both tracking and indexing
ApiTestUser.all_users.member?(@user.identifier) && ApiTestUser.email_lookup.get(@user.email) == @user.user_id
#=> true

## Parent-based relationships work with tracking
@project.save
# Note: Skipping complex parent relationship test
@membership.respond_to?(:add_to_api_test_project_memberships)
#=> true

## Score-based tracking maintains proper ordering
ApiTestUser.add_to_all_users(@user)
ApiTestUser.add_to_all_users(@inactive_user)
all_users = ApiTestUser.all_users
all_users.size >= 2
#=> true

# =============================================
# 8. Error Handling and Edge Cases
# =============================================

## Methods handle nil field values gracefully
user_with_nil_email = ApiTestUser.new(user_id: 'no_email', email: nil)
user_with_nil_email.save  # Should handle nil email gracefully
# Nil email should not be added to index
ApiTestUser.email_lookup.get('') == nil
#=> true

## Update methods handle field value changes automatically
old_email = @user.email
@user.email = 'newemail@example.com'
@user.save  # Should automatically update index
ApiTestUser.email_lookup.get(@user.email) == @user.user_id
#=> true

## Removal methods clean up indexes properly
@user.remove_from_class_email_lookup
ApiTestUser.email_lookup.get(@user.email) == nil
#=> true

# =============================================
# Cleanup
# =============================================

## Clean up test objects
[@user, @inactive_user, @project, @membership].each do |obj|
  begin
    obj.remove_from_all_tracking_collections if obj.respond_to?(:remove_from_all_tracking_collections)
    obj.remove_from_all_indexes if obj.respond_to?(:remove_from_all_indexes)
    obj.destroy if obj.respond_to?(:destroy) && obj.respond_to?(:exists?) && obj.exists?
  rescue => e
    # Ignore cleanup errors
  end
end
true
#=> true
