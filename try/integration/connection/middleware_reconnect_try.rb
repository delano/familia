# try/integration/connection/middleware_reconnect_try.rb
#
# frozen_string_literal: true

# Tests for Familia.reconnect! method that refreshes connection pools
# with current middleware configuration

require_relative '../../support/helpers/test_helpers'
require 'connection_pool'

# Disable logging for cleaner test output
Familia.enable_database_logging = false

# Test model for middleware reconnection testing
class ReconnectTestUser < Familia::Horreum
  identifier_field :user_id
  field :user_id
  field :name

  def init
    @user_id ||= SecureRandom.hex(4)
  end
end

## Test 5: Middleware re-registration flag is reset and re-set
Familia.enable_database_logging = true
Familia.instance_variable_set(:@middleware_registered, true)
Familia.reconnect!
was_registered = Familia.instance_variable_get(:@middleware_registered)
was_registered
#=> true

## Test 6: reconnect! safely handles no middleware enabled
Familia.enable_database_logging = false
Familia.enable_database_counter = false
Familia.reconnect!
chain_cleared = Familia.instance_variable_get(:@connection_chain).nil?
chain_cleared
#=> true



## Setup: Clean database
ReconnectTestUser.dbclient.flushdb
#=> "OK"

## Test 1: Basic reconnect functionality clears chain and increments version
Familia.enable_database_logging = true
initial = Familia.middleware_version
Familia.reconnect!
chain_cleared = Familia.instance_variable_get(:@connection_chain).nil?
version_incremented = Familia.middleware_version > initial
[chain_cleared, version_incremented]
#=> [true, true]

## Test 2: Reconnect works with connection providers

# Create a simple connection provider
Familia.connection_provider = ->(uri) { Redis.new(url: uri) }

## Reconnect clears chain even with provider
Familia.reconnect!
Familia.instance_variable_get(:@connection_chain)
#=> nil

## Test 3: Verify new connections work after reconnect

# Create user to trigger connection
@user = ReconnectTestUser.new(name: "Bob")
@user.save
#=> true

## User should be retrievable
@retrieved = ReconnectTestUser.find(@user.identifier)
@retrieved.name
#=> "Bob"

## Test 4: Multiple reconnects are safe
Familia.reconnect!
Familia.reconnect!
Familia.reconnect!

## Connection chain should still be cleared (will rebuild on next use)
Familia.instance_variable_get(:@connection_chain)
#=> nil

## Cleanup
Familia.enable_database_logging = false
Familia.connection_provider = nil
