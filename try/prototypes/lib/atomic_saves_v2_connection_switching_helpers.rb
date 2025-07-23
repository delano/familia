# try/prototypes/atomic_saves_v2_connection_switching_helpers.rb

##
# Atomic Save V2 Proof of Concept - Connection Switching Approach
#
# This implementation demonstrates atomic saves across multiple Familia
# objects by switching which Redis connection the `redis` method returns
# based on transaction context.
#
# Key Features:
# 1. **Connection Switching**: The `redis` method returns either normal
#    connection or MULTI connection based on Thread-local context
# 2. **Thread Safety**: Uses Thread-local storage for transaction state
# 3. **No method_missing**: Clean implementation via method overriding
# 4. **Redis MULTI/EXEC**: Leverages Redis's native transaction support
#
# Design Decision: TransactionalMethods Module REMOVED
#
# We prefer that nested `Familia.atomic` calls create separate transactions
# rather than being merged into the parent transaction. This provides clearer
# transaction boundaries and more predictable behavior:
#
# Familia.atomic do
#   account.save              # Transaction 1
#
#   Familia.atomic do
#     account.batch_update()  # Transaction 2 (separate)
#   end
# end
#
# This approach avoids the complexity of the TransactionalMethods module
# and makes transaction scope explicit and predictable.


# Test models first - define before any module modifications
class BankAccount < Familia::Horreum
  identifier :account_number
  field :account_number
  field :balance
  field :holder_name

  def initialize(account_number: nil, balance: 0, holder_name: nil)
    @account_number = account_number || SecureRandom.hex(8)
    @balance = balance.to_f
    @holder_name = holder_name
  end

  def withdraw(amount)
    raise "Insufficient funds" if balance < amount
    self.balance -= amount
  end

  def deposit(amount)
    self.balance += amount
  end
end

class TransactionRecord < Familia::Horreum
  identifier :transaction_id
  field :transaction_id
  field :from_account
  field :to_account
  field :amount
  field :status
  field :created_at

  def initialize(from: nil, to: nil, amount: 0)
    @transaction_id = SecureRandom.hex(8)
    @from_account = from
    @to_account = to
    @amount = amount.to_f
    @status = "pending"
    @created_at = Time.now.to_i
  end
end

# Atomic Save V2 - Connection-switching approach
module Familia
  class << self
    def current_transaction
      Thread.current[:familia_current_transaction]
    end

    def current_transaction=(transaction)
      Thread.current[:familia_current_transaction] = transaction
    end

    def atomic(&block)
      if current_transaction
        # Already in a transaction, just execute the block
        yield
      else
        # Use Redis multi with block form
        redis.multi do |multi|
          begin
            self.current_transaction = multi
            yield
          ensure
            self.current_transaction = nil
          end
        end
      end
    end
  end

  # Override the redis method in both base classes
  module TransactionalRedis
    def redis
      Familia.current_transaction || super
    end
  end

  # Inject into Horreum - TransactionalMethods module removed per design decision
  class Horreum
    module Serialization
      prepend TransactionalRedis
    end
  end

  # Inject into RedisType
  class RedisType
    prepend TransactionalRedis
  end
end
