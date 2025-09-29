# Transaction Fallback Integration Tryouts
#
# Tests real-world scenarios where transaction fallback is needed, particularly
# focusing on save operations, relationship updates, and other high-level
# operations that internally use transactions.
#
# These tests verify that the transaction mode configuration works seamlessly
# with Familia's existing features when connection handlers don't support
# transactions (e.g., cached connections, middleware connections).

require_relative '../helpers/test_helpers'

# Setup - store original values
$original_transaction_mode = Familia.transaction_mode
$original_provider = Familia.connection_provider

# Create test classes for integration testing
class IntegrationTestUser < Familia::Horreum
  identifier_field :user_id
  field :user_id
  field :name
  field :email
  field :status
  list :activity_log
  set :tags
  zset :scores
end

class IntegrationTestSession < Familia::Horreum
  identifier_field :session_id
  field :session_id
  field :user_id
  field :created_at
  field :expires_at
end

## Save operation works with transaction fallback in warn mode
begin
  Familia.configure { |config| config.transaction_mode = :warn }

  # Force CachedConnectionHandler
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(
    user_id: 'save_test_001',
    name: 'Test User',
    email: 'test@example.com',
    status: 'active'
  )

  # Save internally uses transactions for atomicity
  result = user.save

  # Should complete successfully using individual commands
  result && user.exists?
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Save operation works with transaction fallback in permissive mode
begin
  Familia.configure { |config| config.transaction_mode = :permissive }

  # Force CachedConnectionHandler
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(
    user_id: 'save_test_002',
    name: 'Permissive User',
    email: 'permissive@example.com'
  )

  # Should save silently using individual commands
  result = user.save

  result && user.exists?
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Multiple field updates work with fallback
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(user_id: 'update_test_001')
  user.save

  # Update multiple fields - should use individual commands
  user.name = 'Updated Name'
  user.email = 'updated@example.com'
  user.status = 'updated'

  result = user.save

  # Verify all fields were updated
  reloaded_user = IntegrationTestUser.load('update_test_001')
  result &&
  reloaded_user.name == 'Updated Name' &&
  reloaded_user.email == 'updated@example.com' &&
  reloaded_user.status == 'updated'
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Data type operations work with transaction fallback
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(user_id: 'datatype_test_001')
  user.save

  # Test list operations
  user.activity_log.add('user_created')
  user.activity_log.add('profile_updated')

  # Test set operations
  user.tags.add('premium')
  user.tags.add('verified')

  # Test sorted set operations
  user.scores.add('game_score', 100)
  user.scores.add('quiz_score', 85)

  # Verify all operations worked
  user.activity_log.size == 2 &&
  user.tags.include?('premium') &&
  user.scores.score('game_score') == 100.0
ensure
  # Clean up test data
  begin
    IntegrationTestUser.destroy!('datatype_test_001')
  rescue => e
    # Ignore cleanup errors
  end
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Connection provider integration with transaction modes
begin
  Familia.configure { |config| config.transaction_mode = :warn }

  # Set up connection provider that doesn't support transactions
  test_connections = {}
  Familia.connection_provider = lambda do |uri|
    test_connections[uri] ||= Familia.create_dbclient(uri)
  end

  user = IntegrationTestUser.new(
    user_id: 'provider_test_001',
    name: 'Provider Test User'
  )

  # Should work with connection provider
  result = user.save

  result && user.exists?
ensure
  Familia.connection_provider = $original_provider
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Mixed connection handlers in same operation
begin
  Familia.configure { |config| config.transaction_mode = :permissive }

  # User class with cached connection (fallback mode)
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  # Session class without cached connection (normal mode)
  user = IntegrationTestUser.new(user_id: 'mixed_test_001')
  session = IntegrationTestSession.new(
    session_id: 'sess_mixed_001',
    user_id: 'mixed_test_001',
    created_at: Time.now.to_i
  )

  # Both should save successfully despite different connection handlers
  user_saved = user.save
  session_saved = session.save

  user_saved && session_saved && user.exists? && session.exists?
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Transaction mode changes during runtime
begin
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(user_id: 'runtime_test_001')

  # Start in strict mode - should fail
  Familia.configure { |config| config.transaction_mode = :strict }
  strict_failed = false
  begin
    user.transaction { |conn| conn.set('test_key', 'test_value') }
  rescue Familia::OperationModeError
    strict_failed = true
  end

  # Switch to permissive mode - should work
  Familia.configure { |config| config.transaction_mode = :permissive }
  result = user.transaction { |conn| conn.set('test_key', 'test_value') }
  permissive_worked = result.successful?

  strict_failed && permissive_worked
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Large batch operations with transaction fallback
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(user_id: 'batch_test_001')

  # Simulate a large batch operation that would normally use transactions
  result = user.transaction do |conn|
    # Add multiple activity log entries
    (1..10).each do |i|
      conn.rpush(user.activity_log.dbkey, "activity_#{i}")
    end

    # Add multiple tags
    %w[tag1 tag2 tag3 tag4 tag5].each do |tag|
      conn.sadd(user.tags.dbkey, tag)
    end

    # Add user fields
    conn.hset(user.dbkey, 'batch_processed', 'true')
  end

  # Should complete successfully and return MultiResult
  result.is_a?(MultiResult) && result.successful?
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

## Error handling in individual command mode
begin
  Familia.configure { |config| config.transaction_mode = :permissive }
  IntegrationTestUser.instance_variable_set(:@dbclient, Familia.create_dbclient)

  user = IntegrationTestUser.new(user_id: 'error_test_001')

  # Execute commands where some might fail
  result = user.transaction do |conn|
    conn.hset(user.dbkey, 'field1', 'value1')  # Should succeed

    # This might fail but shouldn't stop other commands
    begin
      conn.incr('non_numeric_key')  # Might fail if key exists as string
    rescue => e
      # Individual commands can handle their own errors
    end

    conn.hset(user.dbkey, 'field2', 'value2')  # Should succeed
  end

  # Should return MultiResult even with mixed success/failure
  result.is_a?(MultiResult)
ensure
  IntegrationTestUser.remove_instance_variable(:@dbclient)
  Familia.configure { |config| config.transaction_mode = :strict }
end
#=> true

# Cleanup - restore original settings
Familia.configure { |config| config.transaction_mode = $original_transaction_mode }
Familia.connection_provider = $original_provider
