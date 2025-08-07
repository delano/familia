# try/features/real_feature_integration_try.rb

require_relative '../helpers/test_helpers'

Familia.debug = false

# Real feature integration: expiration feature works with new system
class ExpirationIntegrationTest < Familia::Horreum
  identifier_field :id
  field :id
  field :name
  feature :expiration
end

# Safe dump feature integration with field categories
class SafeDumpCategoryTest < Familia::Horreum
  identifier_field :id
  field :id
  field :public_name, category: :persistent
  field :email, category: :encrypted
  field :tryouts_cache_data, category: :transient

  feature :safe_dump

  @safe_dump_fields = [
    :id,
    :public_name,
    :email
  ]
end

# Combined features work together
class CombinedFeaturesTest < Familia::Horreum
  identifier_field :id
  field :id
  field :name, category: :persistent
  field :temp_data, category: :transient

  feature :expiration
  feature :safe_dump

  @safe_dump_fields = [:id, :name]
end

# Test that individual features can be queried
class QueryFeaturesTest < Familia::Horreum
  identifier_field :id
  field :id
  feature :expiration
end

# Empty features list for class without features
class NoFeaturesTest < Familia::Horreum
  identifier_field :id
  field :id
end

# Error handling for duplicate feature includes
class DuplicateFeatureHandling < Familia::Horreum
  identifier_field :id
  field :id
  feature :expiration
  # This should generate a warning but not error
  feature :expiration
end

@expiration_test = ExpirationIntegrationTest.new(id: 'exp_test_1', name: 'Test')

@safedump_test = SafeDumpCategoryTest.new(
  id: 'safe_test_1',
  public_name: 'Public Name',
  email: 'test@example.com',
  tryouts_cache_data: 'temporary'
)

@combined_test = CombinedFeaturesTest.new(id: 'combined_1', name: 'Combined', temp_data: 'temp')

## Expiration feature is properly registered
Familia::Base.features_available.key?(:expiration)
#=> true

## Feature enabled correctly
ExpirationIntegrationTest.features_enabled.include?(:expiration)
#=> true

## Expiration methods are available
@expiration_test.respond_to?(:update_expiration)
#=> true

## Class methods from expiration feature work
ExpirationIntegrationTest.respond_to?(:default_expiration)
#=> true

## Safe dump feature loaded correctly
SafeDumpCategoryTest.features_enabled.include?(:safe_dump)
#=> true

## Safe dump works with field categories
@safedump_result = @safedump_test.safe_dump
@safedump_result.keys.sort
#=> [:email, :id, :public_name]

## Safe dump respects safe_dump_fields configuration
@safedump_result.key?(:tryouts_cache_data)
#=> false

## Both features are enabled
CombinedFeaturesTest.features_enabled.include?(:expiration)
#=> true

## Safe dump feature also enabled
CombinedFeaturesTest.features_enabled.include?(:safe_dump)
#=> true

## Combined functionality works correctly
@combined_test.safe_dump
#=> { id: "combined_1", name: "Combined" }

## Expiration functionality still available
@combined_test.respond_to?(:update_expiration)
#=> true

## Test that feature() method returns current features when called with no args
CombinedFeaturesTest.feature
#=> [:expiration, :safe_dump]

## Test that features_enabled() method returns the same results as feature() method
CombinedFeaturesTest.feature
#=> [:expiration, :safe_dump]

## Features list is accessible
QueryFeaturesTest.feature
#=> [:expiration]

## No features returns empty array
NoFeaturesTest.feature
#=> []

## Duplicate features handled gracefully
DuplicateFeatureHandling.features_enabled
#=> [:expiration]

@expiration_test.destroy! rescue nil
@safedump_test.destroy! rescue nil
@combined_test.destroy! rescue nil
@expiration_test = nil
@safedump_test = nil
@combined_test = nil
