# try/integration/transaction_safety_core_try.rb
#
# frozen_string_literal: true

# Core Transaction Safety Tests
#
# Tests the fundamental transaction safety rules from docs/transaction_safety.md
# Focuses on the most critical safety mechanisms.
#

require_relative '../support/helpers/test_helpers'

# Simple test model for transaction safety
class ::SafetyTestCustomer < Familia::Horreum
  identifier_field :email
  field :email
  field :login_count
  field :status

  list :orders
end

# Helper for unique test IDs
def safety_test_id(prefix = 'test')
  "#{prefix}_#{Time.now.to_i}_#{rand(1000000)}"
end

## save raises OperationModeError inside transaction
error_raised = false
SafetyTestCustomer.transaction do
  customer = SafetyTestCustomer.new(email: "#{safety_test_id}@example.com")
  begin
    customer.save
  rescue Familia::OperationModeError => e
    error_raised = true
  end
end
error_raised
#=> true

## save_if_not_exists! raises OperationModeError inside transaction
error_raised_conditional = false
SafetyTestCustomer.transaction do
  customer = SafetyTestCustomer.new(email: "#{safety_test_id}@example.com")
  begin
    customer.save_if_not_exists!
  rescue Familia::OperationModeError => e
    error_raised_conditional = true
  end
end
error_raised_conditional
#=> true

## create! raises OperationModeError inside transaction
error_raised_create = false
SafetyTestCustomer.transaction do
  begin
    SafetyTestCustomer.create!(email: "#{safety_test_id}@example.com")
  rescue Familia::OperationModeError => e
    error_raised_create = true
  end
end
error_raised_create
#=> true

## correct pattern save before transaction works
@correct_customer = SafetyTestCustomer.new(email: "#{safety_test_id('correct')}@example.com")
@correct_customer.save
#=> true

## operations work inside transaction after save
@correct_customer.transaction do
  @correct_customer.hset(:login_count, '1')
  @correct_customer.hset(:status, 'active')
end
@correct_customer.hget(:login_count).to_i >= 1
#=> true

## write-only operations work inside transactions
@write_customer = SafetyTestCustomer.new(email: "#{safety_test_id('write')}@example.com")
@write_customer.save

@write_result = @write_customer.transaction do |conn|
  conn.hset(@write_customer.dbkey, 'status', 'premium')
  conn.hset(@write_customer.dbkey, 'login_count', '5')
  conn.expire(@write_customer.dbkey, 3600)
end
@write_result.class.name
#=> "MultiResult"

## nested transactions reuse same connection
@nested_customer = SafetyTestCustomer.new(email: "#{safety_test_id('nested')}@example.com")
@nested_customer.save

@outer_conn_id = nil
@inner_conn_id = nil

SafetyTestCustomer.transaction do |outer_conn|
  @outer_conn_id = outer_conn.object_id
  @nested_customer.hset(:login_count, '1')

  @nested_customer.transaction do |inner_conn|
    @inner_conn_id = inner_conn.object_id
    @nested_customer.hset(:status, 'nested')
  end
end

@outer_conn_id == @inner_conn_id
#=> true

## read operations return Future objects inside transaction
@read_customer = SafetyTestCustomer.new(email: "#{safety_test_id('read')}@example.com")
@read_customer.save

@future_object = nil
@read_customer.transaction do |conn|
  @future_object = conn.hget(@read_customer.dbkey, 'email')
end
@future_object.class.name.include?('Future')
#=> true

## exists check returns Future inside transaction always truthy
@pitfall_customer = SafetyTestCustomer.new(email: "#{safety_test_id('pitfall')}@example.com")

@wrong_result = nil
SafetyTestCustomer.transaction do |conn|
  existence = conn.exists?(@pitfall_customer.dbkey)
  @wrong_result = if existence
    'always_executed'
  else
    'never_executed'
  end
end
@wrong_result
#=> 'always_executed'

## create with success callback works
@callback_executed = false
SafetyTestCustomer.create!(email: "#{safety_test_id('callback')}@example.com") do |customer|
  @callback_executed = true
  customer.hset(:login_count, '1')
end
@callback_executed
#=> true

## multi-object atomic updates work
@order_customer = SafetyTestCustomer.new(email: "#{safety_test_id('order')}@example.com")
@order_customer.save

@multi_result = SafetyTestCustomer.transaction do
  @order_customer.hset(:status, 'confirmed')
  @order_customer.orders.push('order123')
  @order_customer.hset(:login_count, '1')
end
@multi_result.successful?
#=> true

## watch pattern for optimistic locking works
@watch_customer = SafetyTestCustomer.new(email: "#{safety_test_id('watch')}@example.com")
@watch_customer.save
@watch_customer.hset(:balance, '1000')

@success = @watch_customer.watch do
  current_balance = @watch_customer.hget(:balance).to_i

  if current_balance >= 100
    @watch_customer.transaction do
      @watch_customer.hset(:balance, (current_balance - 100).to_s)
      @watch_customer.hset(:purchases, '1')
    end
  end
end

@new_balance = @watch_customer.hget(:balance).to_i
@new_balance <= 900
#=> true
