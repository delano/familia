# lib/familia/horreum/connection.rb

module Familia
  class Horreum
    # Connection - Mixed instance and class-level methods for Valkey connection management
    # Provides connection handling, transactions, and URI normalization for both
    # class-level operations (e.g., Customer.dbclient) and instance-level operations
    # (e.g., customer.dbclient)
    module Connection
      attr_reader :uri

      # Normalizes various URI formats to a consistent URI object
      # Considers the class/instance logical_database when uri is nil or Integer
      def normalize_uri(uri)
        case uri
        when Integer
          new_uri = Familia.uri.dup
          new_uri.db = uri
          new_uri
        when ->(obj) { obj.is_a?(String) || obj.instance_of?(::String) }
          URI.parse(uri)
        when URI
          uri
        when nil
          # Use logical_database if available, otherwise fall back to Familia.uri
          if respond_to?(:logical_database) && logical_database
            new_uri = Familia.uri.dup
            new_uri.db = logical_database
            new_uri
          else
            Familia.uri
          end
        else
          raise ArgumentError, "Invalid URI type: #{uri.class.name}"
        end
      end

      # Creates a new Database connection instance using the class/instance configuration
      def create_dbclient(uri = nil)
        parsed_uri = normalize_uri(uri)
        Familia.create_dbclient(parsed_uri)
      end

      # Returns the Database connection for the class using Chain of Responsibility pattern.
      #
      # This method uses a chain of handlers to resolve connections in priority order:
      # 1. FiberTransactionHandler - Fiber[:familia_transaction] (active transaction)
      # 2. DefaultConnectionHandler - Horreum model class-level @dbclient
      # 3. GlobalFallbackHandler - Familia.dbclient(uri || logical_database) (global fallback)
      #
      # @return [Redis] the Database connection instance.
      #
      def dbclient(uri = nil)
        @class_connection_chain ||= build_connection_chain
        @class_connection_chain.handle(uri)
      end

      def connect(*)
        create_dbclient(*)
      end

      def uri=(uri)
        @uri = normalize_uri(uri)
      end
      alias url uri
      alias url= uri=

      # Perform a sacred Database transaction ritual.
      #
      # This method creates a protective circle around your Database operations,
      # ensuring they all succeed or fail together. It's like a group hug for your
      # data operations, but with more ACID properties.
      #
      # @yield [conn] A block where you can perform your Database incantations.
      # @yieldparam conn [Redis] A Database connection in multi mode.
      #
      # @example Performing a Database rain dance
      #   transaction do |conn|
      #     conn.set("weather", "rainy")
      #     conn.set("mood", "melancholic")
      #   end
      #
      # @note This method works with the global Familia.transaction context when available
      #
      # Executes a Redis transaction (MULTI/EXEC) using this object's connection context.
      #
      # Provides atomic execution of multiple Redis commands with automatic connection
      # management and operation mode enforcement. Uses the object's database and
      # connection settings. Returns a MultiResult object for consistency with global methods.
      #
      # @param [Proc] block The block containing Redis commands to execute atomically
      # @yield [Redis] conn The Redis connection configured for transaction mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #   (e.g., FiberConnectionHandler or DefaultConnectionHandler that don't support transactions)
      #
      # @example Basic instance transaction
      #   customer = Customer.new(custid: 'cust_123')
      #   result = customer.transaction do |conn|
      #     conn.hset(customer.dbkey, 'name', 'John Doe')
      #     conn.hset(customer.dbkey, 'email', 'john@example.com')
      #     conn.hget(customer.dbkey, 'name')
      #   end
      #   result.successful?    # => true
      #   result.results        # => ["OK", "OK", "John Doe"]
      #
      # @example Using with object's database context
      #   class Customer < Familia::Horreum
      #     logical_database 5  # Use database 5
      #     field :name
      #     field :email
      #   end
      #
      #   customer = Customer.new(custid: 'cust_456')
      #   result = customer.transaction do |conn|
      #     # Commands automatically execute in database 5
      #     conn.hset(customer.dbkey, 'status', 'active')
      #     conn.sadd('active_customers', customer.identifier)
      #   end
      #   result.successful?    # => true
      #
      # @example Reentrant behavior with global transactions
      #   customer = Customer.new(custid: 'cust_789')
      #
      #   # When called within a global transaction, reuses the transaction connection
      #   result = Familia.transaction do |global_conn|
      #     global_conn.set('global_key', 'value')
      #
      #     # This reuses the same transaction connection
      #     customer.transaction do |local_conn|
      #       local_conn.hset(customer.dbkey, 'updated', Time.now.to_i)
      #       'local_return_value'  # Returned directly in nested context
      #     end
      #   end
      #
      # @note Connection Inheritance:
      #   - Uses object's logical_database setting if configured
      #   - Inherits class-level database settings
      #   - Falls back to instance-level dbclient if set
      #   - Uses global connection chain as final fallback
      #
      # @note Transaction Context:
      #   - When called outside global transaction: Creates local MultiResult
      #   - When called inside global transaction: Yields to existing transaction
      #   - Maintains proper Fiber-local state for nested calls
      #
      # @see Familia.transaction For global transaction method
      # @see MultiResult For details on the return value structure
      # @see #batch_update For similar atomic field updates with MultiResult
      def transaction(&)
        Familia::Connection::TransactionCore.execute_transaction(-> { dbclient }, &)
      end
      alias multi transaction

      # Executes Redis commands in a pipeline using this object's connection context.
      #
      # Batches multiple Redis commands together and sends them in a single network
      # round-trip for improved performance. Uses the object's database and connection
      # settings. Returns a MultiResult object for consistency with global methods.
      #
      # @param [Proc] block The block containing Redis commands to execute in pipeline
      # @yield [Redis] conn The Redis connection configured for pipelined mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #   (e.g., FiberConnectionHandler or CachedConnectionHandler that don't support pipelines)
      #
      # @example Basic instance pipeline
      #   customer = Customer.new(custid: 'cust_123')
      #   result = customer.pipelined do |conn|
      #     conn.hset(customer.dbkey, 'last_login', Time.now.to_i)
      #     conn.hincrby(customer.dbkey, 'login_count', 1)
      #     conn.sadd('recent_logins', customer.identifier)
      #     conn.hget(customer.dbkey, 'login_count')
      #   end
      #   result.successful?        # => true
      #   result.results           # => ["OK", 15, "OK", "15"]
      #   result.results.last      # => "15" (new login count)
      #
      # @example Performance optimization for object operations
      #   user = User.new(userid: 'user_456')
      #
      #   # Instead of multiple round-trips:
      #   # user.save                    # Round-trip 1
      #   # user.tags.add('premium')     # Round-trip 2
      #   # user.sessions.clear          # Round-trip 3
      #
      #   # Use pipeline for single round-trip:
      #   result = user.pipelined do |conn|
      #     conn.hmset(user.dbkey, user.to_h_for_storage)
      #     conn.sadd(user.tags.dbkey, 'premium')
      #     conn.del(user.sessions.dbkey)
      #   end
      #   # All operations completed in one network round-trip
      #
      # @example Using with object's database context
      #   class Session < Familia::Horreum
      #     logical_database 3  # Use database 3
      #     field :user_id
      #     field :expires_at
      #   end
      #
      #   session = Session.new(session_id: 'sess_789')
      #   result = session.pipelined do |conn|
      #     # Commands automatically execute in database 3
      #     conn.hset(session.dbkey, 'user_id', 'user_123')
      #     conn.hset(session.dbkey, 'expires_at', 1.hour.from_now.to_i)
      #     conn.expire(session.dbkey, 3600)
      #   end
      #
      # @example Reentrant behavior with global pipelines
      #   customer = Customer.new(custid: 'cust_abc')
      #
      #   # When called within a global pipeline, reuses the pipeline connection
      #   result = Familia.pipelined do |global_conn|
      #     global_conn.set('global_counter', 0)
      #
      #     # This reuses the same pipeline connection
      #     customer.pipelined do |local_conn|
      #       local_conn.hset(customer.dbkey, 'updated', Time.now.to_i)
      #       Redis::Future.new  # Returns Redis::Future in nested context
      #     end
      #   end
      #
      # @note Connection Inheritance:
      #   - Uses object's logical_database setting if configured
      #   - Inherits class-level database settings
      #   - Falls back to instance-level dbclient if set
      #   - Uses global connection chain as final fallback
      #
      # @note Pipeline Context:
      #   - When called outside global pipeline: Creates local MultiResult
      #   - When called inside global pipeline: Yields to existing pipeline
      #   - Maintains proper Fiber-local state for nested calls
      #
      # @note Performance Considerations:
      #   - Best for multiple independent operations on the same object
      #   - Reduces network latency by batching commands
      #   - Commands execute independently (some may succeed, others fail)
      #
      # @see Familia.pipelined For global pipeline method
      # @see MultiResult For details on the return value structure
      # @see Familia.transaction For atomic command execution
      def pipelined(&block)
        Familia::Connection::PipelineCore.execute_pipeline(-> { dbclient }, &block)
      end
      alias pipeline pipelined

      private

      # Builds the class-level connection chain with handlers in priority order
      def build_connection_chain
        # Cache handlers at class level to avoid creating new instances per model instance
        @fiber_connection_handler ||= Familia::Connection::FiberConnectionHandler.new
        @provider_connection_handler ||= Familia::Connection::ProviderConnectionHandler.new

        # Determine the appropriate class context
        # When called from instance: self is instance, self.class is the model class
        # When called from class: self is the model class
        klass = self.is_a?(Class) ? self : self.class

        # Always check class first for @dbclient since instance-level connections were removed
        @cached_connection_handler ||= Familia::Connection::CachedConnectionHandler.new(klass)
        @create_connection_handler ||= Familia::Connection::CreateConnectionHandler.new(klass)

        Familia::Connection::ResponsibilityChain.new
          .add_handler(Familia::Connection::FiberTransactionHandler.instance)
          .add_handler(@fiber_connection_handler)
          .add_handler(@provider_connection_handler)
          .add_handler(@cached_connection_handler)
          .add_handler(@create_connection_handler)
      end
    end
  end
end
