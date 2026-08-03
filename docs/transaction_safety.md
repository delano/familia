# Transaction Safety in Familia

## Overview

Familia uses Redis transactions (MULTI/EXEC) for atomic operations. However, Redis transactions have a fundamental limitation: commands within a transaction return `Redis::Future` objects instead of actual values. These Future objects cannot be inspected until the transaction completes.

## Core Rules

### 1. No Save Operations Inside Transactions

**Rule**: The following methods cannot be called within a transaction context:
- `save`
- `save!`
- `save_if_not_exists!`
- `create!` (calls `save_if_not_exists!` internally)

**Rationale**: These methods need to read current state for validation (checking existence, validating unique constraints), which would return uninspectable Redis::Future objects inside transactions.

**Error**: Calling these methods inside a transaction raises `Familia::OperationModeError`

**Correct Pattern**:
```ruby
# ✅ GOOD: Save before transaction
customer = Customer.new(email: 'test@example.com')
customer.save  # Validates unique constraints here

customer.transaction do
  # Perform other atomic operations
  customer.increment(:login_count)
  customer.hset(:last_login, Familia.now.to_i)
end

# ❌ BAD: Save inside transaction
Customer.transaction do
  customer = Customer.new(email: 'test@example.com')
  customer.save  # Raises Familia::OperationModeError
end
```

### 2. Unique Index Guards Run Before Transactions

**Rule**: Unique constraint validation (`guard_unique_indexes!`) and the server-side claim (`claim_unique_<index>!`) must execute outside transaction context.

**Rationale**: Guards need to read current index state to check for duplicates, and the claim's CAS verdict must be inspectable. Inside a transaction, both return Redis::Future objects that cannot be inspected.

**Implementation**: `save` — and the partial writers `commit_fields`, `save_fields`, and `multi_field_update` — automatically guard and claim BEFORE starting their internal transaction, then re-affirm the claim inside it.

### 3. Create with Success Callback

**Pattern**: Use the block form of `create!` for additional operations:

```ruby
Customer.create!(email: 'new@example.com') do |customer|
  # This block only runs if creation succeeded
  customer.add_to_premium_group
  NotificationService.send_welcome_email(customer)
end
```

### 4. Transaction-Safe vs Unsafe Methods

#### Transaction-Safe (can be called inside transactions):
- Write-only operations: `hmset`, `hdel`, `expire`, `hset`
- Predictable operations: `increment`, `decrement`
- Collection operations: `add`, `remove`, `push`
- Instance-scoped index operations: `add_to_company_badge_index` (validation skipped)

#### Transaction-Unsafe (must be called outside transactions):
- Read operations that need immediate values: `exists?`, `hget`, `size`
- Validation operations: `guard_unique_indexes!`, `claim_unique_<index>!`
- Save operations: `save`, `save_if_not_exists!`, `create!`
- Fast writers (`field!`) on fields backing a class-level index — raise
  `Familia::IndexedFieldFastWriteError` inside a transaction or pipeline,
  since the index claim cannot run there

### 5. Handling Nested Transactions

**Behavior**: Familia uses reentrant transactions. If you're already in a transaction, nested transaction calls reuse the same connection.

```ruby
Customer.transaction do |conn|
  # Outer transaction
  customer.increment(:counter)

  customer.transaction do |inner_conn|
    # Same connection as outer - no new MULTI/EXEC
    customer.decrement(:other_counter)
  end
end
```

## Examples

### Example 1: Correct Usage with Unique Constraints

```ruby
# Create with unique email constraint
begin
  customer = Customer.create!(email: 'user@example.com')
  puts "Created customer: #{customer.email}"
rescue Familia::RecordExistsError => e
  puts "Customer already exists: #{e.message}"
end
```

### Example 2: Atomic Multi-Object Updates

```ruby
# Save all objects first
order = Order.new(order_id: 'ORD-123')
order.save

inventory = Inventory.find('ITEM-456')

# Then use transaction for atomic updates
Order.transaction do
  order.hset(:status, 'confirmed')
  inventory.decrement(:quantity, 1)
  order.add_to_daily_orders
end
```

### Example 3: Bulk Creation Pattern

```ruby
# Claim each unique value outside the transaction. The claim is a
# server-side compare-and-set: the loser of a concurrent race raises
# Familia::RecordExistsError here, before anything is written.
customers = emails.map do |email|
  customer = Customer.new(email: email)
  customer.claim_unique_email_lookup!
  customer
end

# Then save atomically. The in-transaction index write is legal only
# because it re-affirms the claim taken above (see ADR-0002); without
# a claim, add_to_class_* raises Familia::OperationModeError.
Customer.transaction do
  customers.each do |customer|
    # Direct write operations only - no save!
    customer.hmset(customer.to_h_for_storage)
    customer.add_to_class_email_lookup
  end
end
```

### Example 4: Instance-Scoped Bulk Indexing

```ruby
# Instance-scoped indexes can be added within transactions
# Uniqueness validation is automatically skipped inside transactions
Company.transaction do
  employees.each do |employee|
    # Safe: validation skipped, direct index write only
    employee.add_to_company_badge_index(company)
  end
end
```

## Common Pitfalls

### Pitfall 1: Checking Existence in Transaction
```ruby
# ❌ WRONG
Customer.transaction do
  unless customer.exists?  # Returns Redis::Future, always truthy!
    customer.save
  end
end

# ✅ CORRECT
unless customer.exists?
  customer.save
end
```

### Pitfall 2: Creating in Transaction
```ruby
# ❌ WRONG
Customer.transaction do
  Customer.create!(email: 'test@example.com')  # Raises OperationModeError
end

# ✅ CORRECT
customer = Customer.create!(email: 'test@example.com')
customer.transaction do
  # Additional operations
end
```

## Migration Guide

If you have code that saves within transactions:

1. Move save operations outside the transaction
2. Use the transaction for atomic updates only
3. Validate constraints before entering the transaction
4. Use write-only operations inside the transaction

## See Also

- [Familia::OperationModeError](../lib/familia/errors.rb)
- [Transaction Implementation](../lib/familia/connection/transaction_core.rb)
- [Unique Index Guards](../lib/familia/features/relationships/indexing/unique_index_generators.rb)
