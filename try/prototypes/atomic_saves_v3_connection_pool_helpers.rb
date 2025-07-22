# try/prototypes/atomic_saves_v3_connection_pool_helpers.rb

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

# Simulate ConnectionPool for testing without adding gem dependency
class ConnectionPool
  def initialize(options = {}, &block)
    @size = options[:size] || 5
    @timeout = options[:timeout] || 5
    @creation_block = block || -> { Redis.new }
    @pool = Array.new(@size) { @creation_block.call }
    @available = @pool.dup
    @mutex = Mutex.new
  end
  
  attr_reader :size
  
  def with(&block)
    conn = checkout
    begin
      yield(conn)
    ensure
      checkin(conn)
    end
  end
  
  private
  
  def checkout
    @mutex.synchronize do
      if @available.empty?
        @creation_block.call
      else
        @available.pop
      end
    end
  end
  
  def checkin(conn)
    @mutex.synchronize do
      @available.push(conn) if @available.size < @size
    end
  end
end

# Test models
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
        # Use connection pool to get connection and start transaction
        connection_pool.with do |conn|
          conn.multi do |multi|
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

    # Explicit approach - connection passed to block
    def atomic_explicit(&block)
      connection_pool.with do |conn|
        conn.multi do |multi|
          yield(multi)
        end
      end
    end

    # Helper for separate nested transactions
    def atomic_separate(&block)
      connection_pool.with do |conn|
        conn.multi do |multi|
          begin
            old_transaction = current_transaction
            self.current_transaction = multi
            yield
          ensure
            self.current_transaction = old_transaction
          end
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
    module Serialization
      prepend ConnectionPoolRedis
    end
  end

  # Inject into RedisType for proxy approach  
  class RedisType
    prepend ConnectionPoolRedis
  end
end