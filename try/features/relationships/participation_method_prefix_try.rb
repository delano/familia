# try/features/relationships/participation_method_prefix_try.rb
#
# frozen_string_literal: true

require_relative '../../../lib/familia'

# Test the method_prefix: option for participates_in
# This allows shorter reverse method names for namespaced classes

# Simulate a namespaced target class
module ::Admin
  class MethodPrefixTeam < Familia::Horreum
    feature :relationships

    identifier_field :team_id
    field :team_id
    field :name

    sorted_set :members
    sorted_set :admins

    def init
      @team_id ||= "team_#{SecureRandom.hex(4)}"
    end
  end
end

# Test class using method_prefix: option
class ::MethodPrefixUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email

  # Use method_prefix to get shorter method names
  # Instead of admin_method_prefix_team_instances, we get team_instances
  participates_in Admin::MethodPrefixTeam, :members, method_prefix: :team

  def init
    @user_id ||= "user_#{SecureRandom.hex(4)}"
  end
end

# Test class using as: which should take precedence over method_prefix:
class ::MethodPrefixPriorityUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email

  # as: takes precedence over method_prefix:
  participates_in Admin::MethodPrefixTeam, :admins, method_prefix: :team, as: :my_teams

  def init
    @user_id ||= "user_#{SecureRandom.hex(4)}"
  end
end

# Test class without method_prefix (default behavior)
class ::MethodPrefixDefaultUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :email

  # Default: uses config_name (admin_method_prefix_team)
  participates_in Admin::MethodPrefixTeam, :members

  def init
    @user_id ||= "user_#{SecureRandom.hex(4)}"
  end
end

@user = MethodPrefixUser.new(email: 'alice@example.com')
@priority_user = MethodPrefixPriorityUser.new(email: 'bob@example.com')
@default_user = MethodPrefixDefaultUser.new(email: 'charlie@example.com')
@team = Admin::MethodPrefixTeam.new(name: 'Engineering')

## method_prefix: generates shortened method names
# The method_prefix: :team option should generate team_* methods
@user.respond_to?(:team_instances)
#=> true

## method_prefix: generates team_ids method
@user.respond_to?(:team_ids)
#=> true

## method_prefix: generates team? method
@user.respond_to?(:team?)
#=> true

## method_prefix: generates team_count method
@user.respond_to?(:team_count)
#=> true

## method_prefix: does NOT generate verbose config_name methods
# The verbose admin_method_prefix_team_* methods should not be created
@user.respond_to?(:admin_method_prefix_team_instances)
#=> false

## as: takes precedence over method_prefix:
# When both as: and method_prefix: are provided, as: wins
@priority_user.respond_to?(:my_teams_instances)
#=> true

## as: takes precedence - method_prefix method NOT generated
@priority_user.respond_to?(:team_instances)
#=> false

## default behavior preserved when no method_prefix
# Without method_prefix:, the config_name is used (method_prefix_team)
# Note: config_name uses the class name without namespace
@default_user.respond_to?(:method_prefix_team_instances)
#=> true

## default behavior - no custom shortened method names
# The team_instances method is not generated unless method_prefix: :team is used
@default_user.respond_to?(:team_instances)
#=> false

## ParticipationRelationship stores method_prefix
# The relationship metadata should include the method_prefix
rel = MethodPrefixUser.participation_relationships.first
rel.method_prefix
#=> :team

## ParticipationRelationship method_prefix is nil for default
rel_default = MethodPrefixDefaultUser.participation_relationships.first
rel_default.method_prefix
#=> nil
