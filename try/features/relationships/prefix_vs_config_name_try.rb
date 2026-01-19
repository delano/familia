# try/features/relationships/prefix_vs_config_name_try.rb
#
# frozen_string_literal: true

# Tests for the bug fix where reverse lookup methods now correctly use `prefix`
# instead of `config_name` for Redis key matching.
#
# Background: When a class declares an explicit `prefix` that differs from its
# computed `config_name`, reverse lookups (like *_instances, *_ids) would fail
# to find the correct keys because they were matching against `config_name`
# instead of `prefix`.
#
# Example: CustomDomain with `prefix :customdomain` (no underscore) vs
# `config_name` returning "custom_domain" (with underscore)

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Scenario 1: Default prefix (no explicit prefix set)
# prefix should equal config_name.to_sym
class ::PrefixTestSimpleModel < Familia::Horreum
  feature :relationships

  identifier_field :model_id
  field :model_id
  field :name

  sorted_set :participants
end

class ::PrefixTestSimpleParticipant < Familia::Horreum
  feature :relationships

  identifier_field :participant_id
  field :participant_id
  field :created_at

  participates_in PrefixTestSimpleModel, :participants, score: :created_at
end

# Scenario 2: Explicit prefix matching config_name
# Should work exactly the same as default
class ::PrefixMatchingTeam < Familia::Horreum
  feature :relationships
  prefix :prefix_matching_team  # Matches config_name

  identifier_field :team_id
  field :team_id
  field :name

  sorted_set :members
end

class ::PrefixMatchingMember < Familia::Horreum
  feature :relationships

  identifier_field :member_id
  field :member_id
  field :joined_at

  participates_in PrefixMatchingTeam, :members, score: :joined_at
end

# Scenario 3: THE BUG CASE - Explicit prefix differs from config_name
# CustomDomain: config_name = "custom_domain", prefix = :customdomain
class ::PrefixMismatchedDomain < Familia::Horreum
  feature :relationships
  prefix :mismatcheddomain  # No underscore - differs from config_name "prefix_mismatched_domain"

  identifier_field :domain_id
  field :domain_id
  field :display_domain
  field :created_at

  participates_in PrefixTestSimpleModel, :participants, score: :created_at
end

# Scenario 4: Another mismatched prefix case - APIKey pattern
# APIKey: config_name = "api_key", prefix = :apikey
class ::PrefixTestAPIKey < Familia::Horreum
  feature :relationships
  prefix :ptapikey  # Differs from config_name "prefix_test_a_p_i_key"

  identifier_field :key_id
  field :key_id
  field :created_at

  sorted_set :authorized_resources
end

class ::PrefixTestAPIResource < Familia::Horreum
  feature :relationships

  identifier_field :resource_id
  field :resource_id
  field :name
  field :created_at

  participates_in PrefixTestAPIKey, :authorized_resources, score: :created_at
end

# Scenario 5: Namespaced class with explicit prefix
# Tests that demodularization doesn't interfere
module ::PrefixTestNS
  class CustomDomain < Familia::Horreum
    feature :relationships
    prefix :ptnscustomdomain  # Explicit, doesn't match "custom_domain"

    identifier_field :domain_id
    field :domain_id
    field :created_at

    participates_in PrefixTestSimpleModel, :participants, score: :created_at
  end
end

# Scenario 6: OAuth2Provider-like - complex snake_case edge case
# config_name would be "o_auth2provider"
class ::PrefixTestOAuthProvider < Familia::Horreum
  feature :relationships
  prefix :ptoauthprovider  # Differs from config_name

  identifier_field :provider_id
  field :provider_id
  field :name

  sorted_set :connected_users
end

class ::PrefixTestOAuthUser < Familia::Horreum
  feature :relationships

  identifier_field :user_id
  field :user_id
  field :connected_at

  participates_in PrefixTestOAuthProvider, :connected_users, score: :connected_at
end

# Setup test instances
@simple_model = PrefixTestSimpleModel.new(model_id: 'model_1', name: 'Test Model')
@simple_participant = PrefixTestSimpleParticipant.new(participant_id: 'part_1', created_at: Familia.now.to_i)

@matching_team = PrefixMatchingTeam.new(team_id: 'team_1', name: 'Engineering')
@matching_member = PrefixMatchingMember.new(member_id: 'member_1', joined_at: Familia.now.to_i)

@mismatched_domain = PrefixMismatchedDomain.new(
  domain_id: 'cd_1',
  display_domain: 'example.com',
  created_at: Familia.now.to_i
)

@api_key = PrefixTestAPIKey.new(key_id: 'key_1', created_at: Familia.now.to_i)
@api_resource = PrefixTestAPIResource.new(
  resource_id: 'res_1',
  name: 'Protected Resource',
  created_at: Familia.now.to_i
)

@ns_domain = PrefixTestNS::CustomDomain.new(domain_id: 'otcd_1', created_at: Familia.now.to_i)

@oauth_provider = PrefixTestOAuthProvider.new(provider_id: 'oauth_1', name: 'Google')
@oauth_user = PrefixTestOAuthUser.new(user_id: 'ouser_1', connected_at: Familia.now.to_i)

# Scenario 1: Default prefix (no explicit prefix set)

## PrefixTestSimpleModel prefix equals config_name as symbol (default behavior)
PrefixTestSimpleModel.prefix
#=> :prefix_test_simple_model

## PrefixTestSimpleModel config_name is snake_case string
PrefixTestSimpleModel.config_name
#=> "prefix_test_simple_model"

## Default prefix matches config_name when converted
PrefixTestSimpleModel.prefix.to_s == PrefixTestSimpleModel.config_name
#=> true

## PrefixTestSimpleParticipant also has default prefix
PrefixTestSimpleParticipant.prefix
#=> :prefix_test_simple_participant

# Scenario 2: Explicit prefix matching config_name

## PrefixMatchingTeam has explicit prefix that matches config_name
PrefixMatchingTeam.prefix
#=> :prefix_matching_team

## PrefixMatchingTeam config_name matches prefix
PrefixMatchingTeam.config_name
#=> "prefix_matching_team"

## Matching prefix and config_name work the same
PrefixMatchingTeam.prefix.to_s == PrefixMatchingTeam.config_name
#=> true

# Scenario 3: THE BUG CASE - Explicit prefix differs from config_name

## PrefixMismatchedDomain has explicit prefix without underscore
PrefixMismatchedDomain.prefix
#=> :mismatcheddomain

## PrefixMismatchedDomain config_name has underscores (snake_case)
PrefixMismatchedDomain.config_name
#=> "prefix_mismatched_domain"

## PrefixMismatchedDomain prefix differs from config_name
PrefixMismatchedDomain.prefix.to_s == PrefixMismatchedDomain.config_name
#=> false

# Scenario 4: PrefixTestAPIKey prefix edge case

## PrefixTestAPIKey has explicit prefix
PrefixTestAPIKey.prefix
#=> :ptapikey

## PrefixTestAPIKey config_name follows snake_case convention
PrefixTestAPIKey.config_name
#=> "prefix_test_api_key"

## PrefixTestAPIKey prefix differs from config_name
PrefixTestAPIKey.prefix.to_s == PrefixTestAPIKey.config_name
#=> false

# Scenario 5: Namespaced class verification

## Namespaced PrefixTestNS::CustomDomain has explicit prefix
PrefixTestNS::CustomDomain.prefix
#=> :ptnscustomdomain

## Namespaced config_name only uses demodularized name
PrefixTestNS::CustomDomain.config_name
#=> "custom_domain"

## Namespaced prefix is distinct from config_name
PrefixTestNS::CustomDomain.prefix.to_s == PrefixTestNS::CustomDomain.config_name
#=> false

# Scenario 6: PrefixTestOAuthProvider edge case

## PrefixTestOAuthProvider has explicit prefix
PrefixTestOAuthProvider.prefix
#=> :ptoauthprovider

## PrefixTestOAuthProvider snake_case config_name
PrefixTestOAuthProvider.config_name
#=> "prefix_test_o_auth_provider"

## PrefixTestOAuthProvider prefix differs from config_name
PrefixTestOAuthProvider.prefix.to_s == PrefixTestOAuthProvider.config_name
#=> false

# Functional tests: Reverse lookups with mismatched prefix/config_name

## Save all test instances for functional tests
[@simple_model, @simple_participant, @matching_team, @matching_member,
 @mismatched_domain, @api_key, @api_resource, @ns_domain,
 @oauth_provider, @oauth_user].each(&:save)
true
#=> true

## Add PrefixTestSimpleParticipant to PrefixTestSimpleModel (default prefix case)
@simple_participant.add_to_prefix_test_simple_model_participants(@simple_model)
@simple_participant.in_prefix_test_simple_model_participants?(@simple_model)
#=> true

## PrefixTestSimpleParticipant reverse lookup finds PrefixTestSimpleModel instances
@simple_participant.prefix_test_simple_model_instances.map(&:identifier)
#=> ["model_1"]

## Add PrefixMatchingMember to PrefixMatchingTeam (matching prefix case)
@matching_member.add_to_prefix_matching_team_members(@matching_team)
@matching_member.in_prefix_matching_team_members?(@matching_team)
#=> true

## PrefixMatchingMember reverse lookup finds PrefixMatchingTeam instances
@matching_member.prefix_matching_team_instances.map(&:identifier)
#=> ["team_1"]

## Add PrefixMismatchedDomain to PrefixTestSimpleModel (THE BUG CASE - mismatched prefix)
@mismatched_domain.add_to_prefix_test_simple_model_participants(@simple_model)
@mismatched_domain.in_prefix_test_simple_model_participants?(@simple_model)
#=> true

## PrefixMismatchedDomain reverse lookup must find PrefixTestSimpleModel via prefix not config_name
@mismatched_domain.prefix_test_simple_model_instances.map(&:identifier)
#=> ["model_1"]

## PrefixMismatchedDomain ids method also works
@mismatched_domain.prefix_test_simple_model_ids
#=> ["model_1"]

## PrefixMismatchedDomain boolean check works
@mismatched_domain.prefix_test_simple_model?
#=> true

## PrefixMismatchedDomain count works
@mismatched_domain.prefix_test_simple_model_count
#=> 1

## Add PrefixTestAPIResource to PrefixTestAPIKey (mismatched prefix case)
@api_resource.add_to_prefix_test_api_key_authorized_resources(@api_key)
@api_resource.in_prefix_test_api_key_authorized_resources?(@api_key)
#=> true

## PrefixTestAPIResource reverse lookup finds PrefixTestAPIKey via prefix not config_name
@api_resource.prefix_test_api_key_instances.map(&:identifier)
#=> ["key_1"]

## Add PrefixTestNS::CustomDomain to PrefixTestSimpleModel (namespaced with mismatched prefix)
@ns_domain.add_to_prefix_test_simple_model_participants(@simple_model)
@ns_domain.in_prefix_test_simple_model_participants?(@simple_model)
#=> true

## PrefixTestNS::CustomDomain reverse lookup finds PrefixTestSimpleModel
@ns_domain.prefix_test_simple_model_instances.map(&:identifier)
#=> ["model_1"]

## Add PrefixTestOAuthUser to PrefixTestOAuthProvider (mismatched prefix case)
@oauth_user.add_to_prefix_test_o_auth_provider_connected_users(@oauth_provider)
@oauth_user.in_prefix_test_o_auth_provider_connected_users?(@oauth_provider)
#=> true

## PrefixTestOAuthUser reverse lookup finds PrefixTestOAuthProvider via prefix
@oauth_user.prefix_test_o_auth_provider_instances.map(&:identifier)
#=> ["oauth_1"]

# Verify dbkey format uses prefix, not config_name

## PrefixTestSimpleModel dbkey uses default prefix (which equals config_name)
@simple_model.dbkey.start_with?("prefix_test_simple_model:")
#=> true

## PrefixMismatchedDomain dbkey uses explicit prefix
@mismatched_domain.dbkey.start_with?("mismatcheddomain:")
#=> true

## PrefixTestAPIKey dbkey uses explicit prefix
@api_key.dbkey.start_with?("ptapikey:")
#=> true

## PrefixTestNS::CustomDomain dbkey uses explicit prefix
@ns_domain.dbkey.start_with?("ptnscustomdomain:")
#=> true

## PrefixTestOAuthProvider dbkey uses explicit prefix
@oauth_provider.dbkey.start_with?("ptoauthprovider:")
#=> true

# Verify participation tracking uses prefix in keys

## PrefixTestSimpleParticipant participations include key with prefix_test_simple_model prefix
@simple_participant_keys = @simple_participant.participations.members
@simple_participant_keys.any? { |k| k.start_with?("prefix_test_simple_model:") }
#=> true

## PrefixMismatchedDomain participations include key with prefix_test_simple_model prefix
@mismatched_domain_keys = @mismatched_domain.participations.members
@mismatched_domain_keys.any? { |k| k.start_with?("prefix_test_simple_model:") }
#=> true

## PrefixTestAPIResource participations include key with ptapikey prefix (not prefix_test_api_key)
@api_resource_keys = @api_resource.participations.members
@api_resource_keys.any? { |k| k.start_with?("ptapikey:") }
#=> true

## PrefixTestOAuthUser participations include key with ptoauthprovider prefix
@oauth_user_keys = @oauth_user.participations.members
@oauth_user_keys.any? { |k| k.start_with?("ptoauthprovider:") }
#=> true

# Bug fix verification: Keys use prefix, NOT config_name
# If the old bug existed, these tests would fail because config_name would be
# used for matching but keys are stored with prefix

## PrefixTestAPIResource keys do NOT contain config_name pattern (prefix_test_api_key)
# This verifies that the key is "ptapikey:..." not "prefix_test_api_key:..."
@api_resource_keys.none? { |k| k.start_with?("prefix_test_api_key:") }
#=> true

## PrefixTestOAuthUser keys do NOT contain config_name pattern
# This verifies that the key is "ptoauthprovider:..." not "prefix_test_o_auth_provider:..."
@oauth_user_keys.none? { |k| k.start_with?("prefix_test_o_auth_provider:") }
#=> true

## PrefixTestAPIKey prefix is different from config_name
# This is the critical condition for the bug: prefix != config_name
PrefixTestAPIKey.prefix.to_s != PrefixTestAPIKey.config_name
#=> true

## PrefixTestOAuthProvider prefix is different from config_name
PrefixTestOAuthProvider.prefix.to_s != PrefixTestOAuthProvider.config_name
#=> true

## participating_ids_for_target finds IDs when prefix differs from config_name
# This is the core bug fix test - the method must use prefix, not config_name
@api_resource.participating_ids_for_target(PrefixTestAPIKey).include?("key_1")
#=> true

## participating_in_target? returns true when prefix differs from config_name
@api_resource.participating_in_target?(PrefixTestAPIKey)
#=> true

## PrefixTestOAuthUser also finds its target despite prefix != config_name
@oauth_user.participating_ids_for_target(PrefixTestOAuthProvider).include?("oauth_1")
#=> true

## PrefixTestOAuthUser participating_in_target? also works
@oauth_user.participating_in_target?(PrefixTestOAuthProvider)
#=> true

## Cleanup test data completes without errors
[@simple_model, @simple_participant, @matching_team, @matching_member,
 @mismatched_domain, @api_key, @api_resource, @ns_domain,
 @oauth_provider, @oauth_user].each do |obj|
  obj.destroy if obj&.respond_to?(:destroy) && obj&.respond_to?(:exists?) && obj.exists?
rescue => e
  # Ignore cleanup errors
end
true
#=> true
