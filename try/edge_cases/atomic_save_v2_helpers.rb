# try/edge_cases/atomic_save_v2_helpers.rb

##
# Summary of Atomic Save V2 Proof of Concept
#
# This implementation successfully demonstrates atomic saves across
# multiple Familia objects by:
#
# 1. **Connection Switching**: The `redis` method returns either the
#    normal connection or a MULTI connection based on context
# 2. **Thread Safety**: Uses Thread-local storage for transaction state
# 3. **No method_missing**: Clean implementation that works with existing
#    code
# 4. **Nested Transaction Support**: Handles nested atomic blocks
#    transparently
# 5. **Compatibility**: Works with existing methods like `batch_update`
#    that use their own transactions
#
# The key insight is that when we're inside `redis.multi do |multi|`,
# all Redis commands sent to the `multi` connection are queued until
# the block completes. By switching which connection the `redis` method
# returns, we can make all existing Familia code work atomically
# without changes.
#
# ### Next Steps for Production:
# 1. Add connection pooling support
# 2. Add transaction retry logic for optimistic locking
# 3. Add deadlock detection and prevention
# 4. Add performance monitoring
# 5. Consider using Redis Lua scripts for complex atomic operations


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

  # Override transaction method to work with atomic context
  module TransactionalMethods
    def transaction(&block)
      if Familia.current_transaction
        # We're already in an atomic context, just yield the current connection
        yield(Familia.current_transaction)
      else
        # Normal transaction behavior
        super(&block)
      end
    end
  end

  # Inject into Horreum
  class Horreum
    module Serialization
      prepend TransactionalRedis
      prepend TransactionalMethods
    end
  end

  # Inject into RedisType
  class RedisType
    prepend TransactionalRedis
  end
end
