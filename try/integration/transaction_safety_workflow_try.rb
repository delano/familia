# try/integration/transaction_safety_workflow_try.rb
#
# frozen_string_literal: true

# Transaction Safety Workflow Integration Test
#
# Demonstrates the complete transaction safety workflow with realistic
# business scenarios that show correct usage patterns.
#

require_relative '../support/helpers/test_helpers'

# Business models for realistic workflow testing
class ::WorkflowCustomer < Familia::Horreum
  identifier_field :customer_id
  field :customer_id
  field :email
  field :balance
  field :status
  field :login_count
  field :last_login

  list :orders
  set :preferences
end

class ::WorkflowOrder < Familia::Horreum
  identifier_field :order_id
  field :order_id
  field :customer_id
  field :amount
  field :status
  field :created_at
end

class ::WorkflowInventory < Familia::Horreum
  identifier_field :product_id
  field :product_id
  field :quantity
  field :reserved
end

# Helper for unique IDs
def workflow_id(prefix = 'wf')
  "#{prefix}_#{Familia.now.to_i}_#{rand(100000)}"
end

## Complete customer registration workflow
@customer_email = "#{workflow_id('customer')}@example.com"
@customer_id = workflow_id('cust')

# Step 1: Create customer (validates uniqueness outside transaction)
@customer = WorkflowCustomer.new(
  customer_id: @customer_id,
  email: @customer_email,
  balance: 1000,
  status: 'pending',
  login_count: 0
)
@customer.save
#=> true

## Customer exists after registration
@customer.exists?
#=> true

## E-commerce order processing workflow
@product_id = workflow_id('prod')
@order_id = workflow_id('order')

# Setup inventory
@inventory = WorkflowInventory.new(
  product_id: @product_id,
  quantity: 50,
  reserved: 0
)
@inventory.save

# Step 1: Create order (outside transaction for validation)
@order = WorkflowOrder.new(
  order_id: @order_id,
  customer_id: @customer_id,
  amount: 99,
  status: 'pending',
  created_at: Familia.now.to_i
)
@order.save
#=> true

## Atomic order processing with inventory update
@processing_result = WorkflowCustomer.transaction do |conn|
  # Update customer
  conn.hset(@customer.dbkey, 'balance', '901')  # 1000 - 99
  conn.hset(@customer.dbkey, 'last_login', Familia.now.to_i.to_s)
  @customer.orders.push(@order_id)

  # Update order
  conn.hset(@order.dbkey, 'status', 'confirmed')

  # Update inventory
  conn.hset(@inventory.dbkey, 'quantity', '49')  # 50 - 1
  conn.hset(@inventory.dbkey, 'reserved', '1')

  # Add customer preference
  @customer.preferences.add('email_notifications')
end
@processing_result.class.name
#=> "MultiResult"

## All updates applied atomically
[@customer.hget('balance').to_i, @order.hget('status'), @inventory.hget('quantity').to_i]
#=> [901, "confirmed", 49]

## Customer login tracking workflow with nested transactions
@login_start = Familia.now

# Read current count outside transaction
@current_count = @customer.hget('login_count').to_i

@customer.transaction do |outer_conn|
  # Outer transaction: main login processing
  outer_conn.hset(@customer.dbkey, 'last_login', @login_start.to_i.to_s)

  # Nested transaction: increment login count (reentrant)
  @customer.transaction do |inner_conn|
    inner_conn.hset(@customer.dbkey, 'login_count', (@current_count + 1).to_s)

    # Add login preference tracking
    @customer.preferences.add('frequent_user') if @current_count > 5
  end

  # Continue outer transaction
  outer_conn.hset(@customer.dbkey, 'status', 'active')
end

@customer.hget('login_count').to_i >= 1
#=> true

## Bulk order fulfillment workflow
@order_ids = 3.times.map { |i| workflow_id("bulk_#{i}") }

# Step 1: Create all orders outside transaction
@bulk_orders = @order_ids.map do |order_id|
  order = WorkflowOrder.new(
    order_id: order_id,
    customer_id: @customer_id,
    amount: 25,
    status: 'pending',
    created_at: Familia.now.to_i
  )
  order.save
  order
end
@bulk_orders.all?(&:exists?)
#=> true

## Bulk fulfillment in single transaction
# Read balance outside transaction
@current_balance = @customer.hget('balance').to_i
@bulk_result = WorkflowOrder.transaction do |conn|
  @bulk_orders.each do |order|
    conn.hset(order.dbkey, 'status', 'fulfilled')
    conn.hset(order.dbkey, 'fulfilled_at', Familia.now.to_i.to_s)
    @customer.orders.push(order.order_id)
  end

  # Update customer balance for all orders
  new_balance = @current_balance - (25 * 3)
  conn.hset(@customer.dbkey, 'balance', new_balance.to_s)
end
@bulk_result.class.name
#=> "MultiResult"

## Error handling in transaction workflow
@error_order_id = workflow_id('error')
@error_handled = false

begin
  WorkflowOrder.transaction do |conn|
    # Valid operation
    conn.hset("test:#{@error_order_id}", 'status', 'processing')

    # Simulate error during processing
    raise StandardError, 'Payment processing failed'

    # This would not execute due to error
    conn.hset("test:#{@error_order_id}", 'status', 'completed')
  end
rescue StandardError => e
  @error_handled = e.message.include?('Payment processing failed')
end

@error_handled
#=> true

## Transaction safety violation detection
@safety_violation_detected = false

WorkflowCustomer.transaction do
  test_customer = WorkflowCustomer.new(
    customer_id: workflow_id('safety'),
    email: "#{workflow_id('safety')}@test.com"
  )

  begin
    # This should raise OperationModeError
    test_customer.save
  rescue Familia::OperationModeError => e
    @safety_violation_detected = e.message.include?('Cannot call save within a transaction')
  end
end

@safety_violation_detected
#=> true

## Performance comparison: individual vs batch operations
@perf_customers = 5.times.map do |i|
  customer = WorkflowCustomer.new(
    customer_id: workflow_id("perf_#{i}"),
    email: "perf#{i}@example.com",
    balance: 1000
  )
  customer.save
  customer
end

# Individual transactions
@individual_start = Familia.now
@perf_customers.each do |customer|
  customer.transaction do |conn|
    conn.hset(customer.dbkey, 'status', 'updated_individual')
  end
end
@individual_duration = ((Familia.now - @individual_start) * 1000).round(2)

# Single batch transaction
@batch_start = Familia.now
WorkflowCustomer.transaction do |conn|
  @perf_customers.each do |customer|
    conn.hset(customer.dbkey, 'status', 'updated_batch')
  end
end
@batch_duration = ((Familia.now - @batch_start) * 1000).round(2)

# Batch should be faster or at least not significantly slower
@efficiency_ratio = @individual_duration / @batch_duration
@efficiency_ratio >= 0.1  # Batch should be reasonably fast
#=> true

## Watch pattern for optimistic concurrency control
@concurrent_customer = WorkflowCustomer.new(
  customer_id: workflow_id('concurrent'),
  email: 'concurrent@test.com',
  balance: 500
)
@concurrent_customer.save
@concurrent_customer.hset(:version, '1')

@watch_success = @concurrent_customer.watch do
  current_version = @concurrent_customer.hget(:version).to_i
  current_balance = @concurrent_customer.hget(:balance).to_i

  # Only proceed if version hasn't changed and sufficient balance
  if current_version == 1 && current_balance >= 100
    @concurrent_customer.transaction do |conn|
      conn.hset(@concurrent_customer.dbkey, 'balance', (current_balance - 100).to_s)
      conn.hset(@concurrent_customer.dbkey, 'version', '2')
      conn.hset(@concurrent_customer.dbkey, 'last_transaction', Familia.now.to_i.to_s)
    end
    true
  else
    false
  end
end

@concurrent_customer.hget(:balance).to_i == 400
#=> true

## Workflow completed successfully with all safety checks
@workflow_summary = {
  customer_created: @customer.exists?,
  order_processed: @order.hget('status') == 'confirmed',
  bulk_fulfilled: @bulk_orders.all? { |o| o.hget('status') == 'fulfilled' },
  error_handled: @error_handled,
  safety_enforced: @safety_violation_detected,
  performance_acceptable: @efficiency_ratio >= 0.1,
  concurrency_controlled: @concurrent_customer.hget(:version).to_i >= 2
}

@workflow_summary.values.all?
#=> true
