# frozen_string_literal: true

module Familia
  # Atomic transaction support with connection pool integration
  #
  # Provides atomic Redis operations using connection pooling for thread safety.
  # Supports both transparent proxy approach and explicit connection passing.
  #
  # Key features:
  # * Thread-safe atomic operations using connection pools
  # * Nested transaction support with separate connections
  # * Both proxy and explicit connection approaches
  # * Automatic DB selection and connection management
  # * Proper error handling and connection cleanup
  #
  # Usage:
  #   # Proxy approach (transparent)
  #   Familia.atomic do
  #     account.withdraw(100)
  #     account.save
  #   end
  #
  #   # Explicit approach (connection passed)
  #   Familia.atomic do |conn|
  #     account.save(using: conn)
  #   end
  #
  module Atomic
    # Gets the current atomic transaction connection from thread-local storage
    # @return [Redis, nil] The current transaction connection or nil
    def current_transaction
      Thread.current[:familia_current_transaction]
    end

    # Sets the current atomic transaction connection in thread-local storage
    # @param connection [Redis, nil] The connection to use for the current transaction
    def current_transaction=(connection)
      Thread.current[:familia_current_transaction] = connection
    end

    # Executes a block within an atomic transaction context.
    # Supports both proxy approach (transparent) and explicit connection passing.
    #
    # @param uri [String, URI, nil] The URI for the Redis server (optional)
    # @param block [Proc] The block to execute atomically
    # @return [Object] The result of the block execution
    # @example Proxy approach (transparent)
    #   Familia.atomic do
    #     account.withdraw(100)
    #     account.save
    #   end
    #
    # @example Explicit connection approach
    #   Familia.atomic do |conn|
    #     account.save(using: conn)
    #   end
    #
    # @example With specific URI
    #   Familia.atomic('redis://localhost:6380') do
    #     # operations on specific server
    #   end
    def atomic(uri = nil, &block)
      if current_transaction
        # Nested atomic - create separate transaction
        atomic_nested(uri, &block)
      else
        atomic_new(uri, &block)
      end
    end

    # Executes a block with an explicit Redis connection from the pool.
    # The connection is passed as an argument to the block.
    # This method always uses a fresh connection, even in nested calls.
    #
    # @param uri [String, URI, nil] The URI for the Redis server
    # @param block [Proc] The block to execute with the connection
    # @return [Object] The result of the block execution
    # @example
    #   Familia.with_connection do |conn|
    #     conn.set('key', 'value')
    #     conn.get('key')
    #   end
    def with_connection(uri = nil, &block)
      target_uri = normalize_uri(uri)
      server_id = server_id_without_db(target_uri)
      target_db = target_uri.db

      # Ensure pool exists
      connect(target_uri) unless @connection_pools[server_id]

      pool = @connection_pools[server_id]

      if enable_connection_pool && pool.is_a?(ConnectionPool)
        pool.with do |conn|
          ensure_db_selected(conn, target_db)
          yield(conn)
        end
      else
        # Direct connection fallback
        conn = pool
        ensure_db_selected(conn, target_db)
        yield(conn)
      end
    end

    # Executes multiple operations atomically using Redis MULTI/EXEC.
    # This provides true atomicity at the Redis level.
    #
    # @param uri [String, URI, nil] The URI for the Redis server
    # @param block [Proc] The block containing Redis operations
    # @return [Array] Array of results from the executed commands
    # @example
    #   results = Familia.multi do |conn|
    #     conn.set('key1', 'value1')
    #     conn.set('key2', 'value2')
    #     conn.incr('counter')
    #   end
    def multi(uri = nil, &block)
      with_connection(uri) do |conn|
        conn.multi(&block)
      end
    end

    # Executes operations in a Redis pipeline for performance.
    # Operations are batched and sent to Redis together.
    #
    # @param uri [String, URI, nil] The URI for the Redis server
    # @param block [Proc] The block containing Redis operations
    # @return [Array] Array of results from the executed commands
    # @example
    #   results = Familia.pipeline do |conn|
    #     conn.set('key1', 'value1')
    #     conn.set('key2', 'value2')
    #     conn.get('key1')
    #   end
    def pipeline(uri = nil, &block)
      with_connection(uri) do |conn|
        conn.pipelined(&block)
      end
    end

    private

    # Executes a new atomic transaction
    def atomic_new(uri, &block)
      target_uri = normalize_uri(uri)

      with_connection(target_uri) do |conn|
        begin
          self.current_transaction = conn

          if block.arity > 0
            # Explicit connection approach
            yield(conn)
          else
            # Proxy approach - connection available via current_transaction
            yield
          end
        ensure
          self.current_transaction = nil
        end
      end
    end

    # Executes a nested atomic transaction with a separate connection
    def atomic_nested(uri, &block)
      target_uri = normalize_uri(uri)

      with_connection(target_uri) do |conn|
        begin
          old_transaction = current_transaction
          self.current_transaction = conn

          if block.arity > 0
            # Explicit connection approach
            yield(conn)
          else
            # Proxy approach - connection available via current_transaction
            yield
          end
        ensure
          self.current_transaction = old_transaction
        end
      end
    end

    # Helper methods that delegate to Connection module

    def normalize_uri(uri)
      send(:normalize_uri, uri)
    end

    def server_id_without_db(uri)
      send(:server_id_without_db, uri)
    end

    def ensure_db_selected(connection, target_db)
      send(:ensure_db_selected, connection, target_db)
    end
  end

  # Proxy module to inject atomic-aware redis method into Horreum/RedisType
  module AtomicProxy
    # Override redis method to use atomic transaction connection when available
    def redis
      Familia.current_transaction || super
    end
  end
end
