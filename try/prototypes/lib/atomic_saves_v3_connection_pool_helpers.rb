# try/prototypes/lib/atomic_saves_v3_connection_pool_helpers.rb

##
# Atomic Save V3 Proof of Concept - Connection Pool Integration
#
# This implementation explores atomic saves with Redis connection pooling
# for thread safety in multi-threaded environments (like Puma).
#
# Key Goals:
# 1. **Connection Pool Integration**: Use ConnectionPool gem for thread safety
# 2. **Dual Approach Testing**: Compare proxy vs explicit connection passing
# 3. **Thread Safety Validation**: Prove pool handles concurrent operations
# 4. **Separate Transaction Boundaries**: Each atomic block gets own transaction
#
# Approaches Tested:
# - Proxy Approach: Familia.atomic { ... } (transparent, V2 style)
# - Explicit Approach: Familia.atomic { |conn| ... } (clear boundaries)

require 'connection_pool'
require 'json'

# Test models
class BankAccount < Familia::Horreum
  identifier :account_number
  field :account_number
  field :balance
  field :holder_name
  field :metadata  # Variable-sized JSON field for workload simulation

  def init
    @account_number ||= SecureRandom.hex(8)
    @balance = @balance.to_f if @balance
    @metadata = @metadata.is_a?(String) ? JSON.parse(@metadata) : @metadata rescue @metadata
  end

  def balance
    @balance&.to_f
  end

  def withdraw(amount)
    raise "Insufficient funds" if balance < amount
    self.balance -= amount
  end

  def deposit(amount)
    self.balance += amount
  end

  def metadata=(value)
    @metadata = value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value
  end

  # Add method that accepts explicit connection
  def save(using: nil)
    if using
      # Use provided connection explicitly
      old_redis = @redis
      @redis = using
      begin
        super()
      ensure
        @redis = old_redis
      end
    else
      # Use normal save behavior
      super()
    end
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

  def amount
    @amount&.to_f
  end

  def created_at
    @created_at&.to_i
  end

  def save(using: nil)
    if using
      old_redis = @redis
      @redis = using
      begin
        super()
      ensure
        @redis = old_redis
      end
    else
      super()
    end
  end
end

module Familia
  # Connection pool for Redis connections
  @@connection_pool = ConnectionPool.new(size: 10, timeout: 5) do
    Redis.new(url: Familia.uri.to_s)
  end

  class << self
    def connection_pool
      @@connection_pool
    end

    def current_transaction
      Thread.current[:familia_current_transaction_v3]
    end

    def current_transaction=(transaction)
      Thread.current[:familia_current_transaction_v3] = transaction
    end

    # Proxy approach - transparent like V2
    def atomic(&block)
      if current_transaction
        # Nested atomic - create separate transaction
        atomic_separate(&block)
      else
        # Use connection pool to get connection
        # For this prototype, we'll use a simple approach that works with Redis
        connection_pool.with do |conn|
          begin
            # Store the connection for use within the block
            self.current_transaction = conn
            result = yield
            result
          ensure
            self.current_transaction = nil
          end
        end
      end
    end

    # Explicit approach - connection passed to block
    def atomic_explicit(&block)
      connection_pool.with do |conn|
        # For this prototype, pass the connection directly
        yield(conn)
      end
    end

    # Helper for separate nested transactions
    def atomic_separate(&block)
      connection_pool.with do |conn|
        begin
          old_transaction = current_transaction
          # Use a separate connection for nested transactions
          self.current_transaction = conn
          result = yield
          result
        ensure
          self.current_transaction = old_transaction
        end
      end
    end
  end

  # Override redis method for proxy approach
  module ConnectionPoolRedis
    def redis
      Familia.current_transaction || super
    end
  end

  # Inject into Horreum for proxy approach
  class Horreum
    prepend ConnectionPoolRedis
  end

  # Inject into DataType for proxy approach
  class DataType
    prepend ConnectionPoolRedis
  end
end
