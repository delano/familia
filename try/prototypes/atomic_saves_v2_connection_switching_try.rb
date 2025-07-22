# try/edge_cases/atomic_save_v2_try.rb

require 'bundler/setup'
require 'securerandom'

require_relative '../helpers/test_helpers'
require_relative 'atomic_saves_v2_connection_switching_helpers'

Familia.debug = false

## Clean database before tests
BankAccount.redis.flushdb
#=> "OK"

## Test 1: Basic atomic save - create accounts
@account1 = BankAccount.new(balance: 1000, holder_name: "Alice")
@account2 = BankAccount.new(balance: 500, holder_name: "Bob")
[@account1.balance, @account2.balance]
#=> [1000.0, 500.0]

## Test 1: Save initial state
[@account1.save, @account2.save]
#=> [true, true]

## Test 1: Perform atomic transfer
@results = Familia.atomic do
  @account1.withdraw(200)
  @account2.deposit(200)
  @account1.save
  @account2.save
end
@results.class
#=> Array

## Test 1: Verify transfer completed atomically
@account1.refresh!
@account2.refresh!
[@account1.balance, @account2.balance]
#=> [800.0, 700.0]

## Test 2: Failed atomic operation - create accounts
@account3 = BankAccount.new(balance: 100, holder_name: "Charlie")
@account4 = BankAccount.new(balance: 500, holder_name: "Dave")
[@account3.balance, @account4.balance]
#=> [100.0, 500.0]

## Test 2: Save initial state
[@account3.save, @account4.save]
#=> [true, true]

## Test 2: Attempt atomic operation that should fail
begin
  Familia.atomic do
    @account3.withdraw(200)
    @account4.deposit(200)
    @account3.save
    @account4.save
  end
  false
rescue => e
  e.message
end
#=> "Insufficient funds"

## Test 2: Verify rollback - balances unchanged
@account3.refresh!
@account4.refresh!
[@account3.balance, @account4.balance]
#=> [100.0, 500.0]

## Test 3: Complex atomic operation - create accounts
@sender = BankAccount.new(balance: 1500, holder_name: "Eve")
@receiver = BankAccount.new(balance: 200, holder_name: "Frank")
[@sender.save, @receiver.save]
#=> [true, true]

## Test 3: Setup transfer amount
@transfer_amount = 750
@transfer_amount
#=> 750

## Test 3: Perform complex atomic operation with transaction record
@results2 = Familia.atomic do
  @txn = TransactionRecord.new(
    from: @sender.account_number,
    to: @receiver.account_number,
    amount: @transfer_amount
  )

  @sender.withdraw(@transfer_amount)
  @receiver.deposit(@transfer_amount)
  @txn.status = "completed"

  [@sender.save, @receiver.save, @txn.save]
end
@results2.class
#=> Array

## Test 3: Verify all changes were applied
@sender.refresh!
@receiver.refresh!
[@sender.balance, @receiver.balance]
#=> [750.0, 950.0]

## Test 3: Verify transaction record was saved
@txn_key = @txn.rediskey
@saved_txn = TransactionRecord.from_redis(@txn_key)
@saved_txn.status
#=> "completed"

## Test 4: Nested context behavior - create account
@account5 = BankAccount.new(balance: 1000, holder_name: "Grace")
@account5.save
#=> true

## Test 4: Perform nested atomic operations
@results3 = Familia.atomic do
  @account5.deposit(100)
  @account5.save

  Familia.atomic do
    @account5.deposit(50)
    @account5.save
  end
end
@results3.class
#=> Array

## Test 4: Verify nested operations worked transparently
@account5.refresh!
@account5.balance
#=> 1150.0

## Test 5: Batch update within atomic context - create account
@account6 = BankAccount.new(balance: 500, holder_name: "Henry")
@account6.save
#=> true

## Test 5: Perform batch update in atomic context
@results4 = Familia.atomic do
  @account6.batch_update(
    balance: 600.0,
    holder_name: "Henry Jr."
  )

  @txn2 = TransactionRecord.new(
    from: "system",
    to: @account6.account_number,
    amount: 100
  )
  @txn2.save
end
@results4.class
#=> Array

## Test 5: Verify batch update and transaction creation
@account6.refresh!
[@account6.balance, @account6.holder_name]
#=> [600.0, "Henry Jr."]
