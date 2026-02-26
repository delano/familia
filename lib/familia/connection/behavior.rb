# lib/familia/connection/behavior.rb
#
# frozen_string_literal: true

# lib/familia/connection/behavior.rb

module Familia
  module Connection
    # Shared connection behavior for both Horreum and DataType classes
    #
    # This module extracts common connection management functionality that was
    # previously duplicated between Horreum::Connection and DataType::Connection.
    # It provides:
    #
    # * URI normalization with logical_database support
    # * Connection creation methods
    # * Transaction and pipeline execution methods
    # * Consistent connection API across object types
    #
    # Classes including this module must implement:
    # * `dbclient(uri = nil)` - Connection resolution method
    # * `build_connection_chain` (private) - Chain of Responsibility setup
    #
    # @example Basic usage in a class
    #   class MyDataStore
    #     include Familia::Connection::Behavior
    #
    #     def dbclient(uri = nil)
    #       @connection_chain ||= build_connection_chain
    #       @connection_chain.handle(uri)
    #     end
    #
    #     private
    #
    #     def build_connection_chain
    #       # ... handler setup ...
    #     end
    #   end
    #
    module Behavior
      def self.included(base)
        base.class_eval do
          attr_writer :dbclient
          attr_reader :uri
        end
      end

      # Normalizes various URI formats to a consistent URI object
      #
      # Handles multiple input types and considers the logical_database setting
      # when uri is nil or Integer. This method is public so connection handlers
      # can use it for consistent URI processing.
      #
      # @param uri [Integer, String, URI, nil] The URI to normalize
      # @return [URI] Normalized URI object
      # @raise [ArgumentError] If URI type is invalid
      #
      # @example Integer database number
      #   normalize_uri(2)  # => URI with db=2 on default server
      #
      # @example String URI
      #   normalize_uri('redis://localhost:6379/1')
      #
      # @example nil with logical_database
      #   class MyModel
      #     include Familia::Connection::Behavior
      #     attr_accessor :logical_database
      #   end
      #   model = MyModel.new
      #   model.logical_database = 3
      #   model.normalize_uri(nil)  # => URI with db=3
      #
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

      # Creates a new Database connection instance
      #
      # This method always creates a fresh connection and does not use caching.
      # Each call returns a new Redis client instance that you are responsible
      # for managing and closing when done.
      #
      # @param uri [String, URI, Integer, nil] The URI of the Database server
      # @return [Redis] A new Database client connection
      #
      # @example Creating a new connection
      #   client = create_dbclient('redis://localhost:6379/1')
      #   client.ping
      #   client.close
      #
      def create_dbclient(uri = nil)
        parsed_uri = normalize_uri(uri)
        Familia.create_dbclient(parsed_uri)
      end

      # Alias for create_dbclient (backward compatibility)
      def connect(*)
        create_dbclient(*)
      end

      # Sets the URI for this object's database connection
      #
      # @param uri [String, URI, Integer] The new URI
      # @return [URI] The normalized URI
      #
      def uri=(uri)
        @uri = normalize_uri(uri)
      end

      # Alias for uri (backward compatibility)
      def url
        uri
      end

      # Alias for uri= (backward compatibility)
      def url=(uri)
        self.uri = uri
      end

      # Executes a Redis transaction (MULTI/EXEC) using this object's connection context
      #
      # Provides atomic execution of multiple Redis commands with automatic connection
      # management and operation mode enforcement. Uses the object's database and
      # connection settings. Returns a MultiResult object for consistency.
      #
      # @yield [Redis] conn The Redis connection configured for transaction mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #
      # @example Basic transaction
      #   obj.transaction do |conn|
      #     conn.set('key1', 'value1')
      #     conn.set('key2', 'value2')
      #     conn.get('key1')
      #   end
      #
      # @example Reentrant behavior
      #   obj.transaction do |conn|
      #     conn.set('outer', 'value')
      #
      #     # Nested transaction reuses same connection
      #     obj.transaction do |inner_conn|
      #       inner_conn.set('inner', 'value')
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
      #
      def transaction(&)
        ensure_relatives_initialized! if respond_to?(:ensure_relatives_initialized!, true)
        Familia::Connection::TransactionCore.execute_transaction(-> { dbclient }, &)
      end

      # Alias for transaction (alternate naming)
      def multi(&)
        transaction(&)
      end

      # Executes Redis commands in a pipeline using this object's connection context
      #
      # Batches multiple Redis commands together and sends them in a single network
      # round-trip for improved performance. Uses the object's database and connection
      # settings. Returns a MultiResult object for consistency.
      #
      # @yield [Redis] conn The Redis connection configured for pipelined mode
      # @return [MultiResult] Result object with success status and command results
      #
      # @raise [Familia::OperationModeError] When called with incompatible connection handlers
      #
      # @example Basic pipeline
      #   obj.pipelined do |conn|
      #     conn.set('key1', 'value1')
      #     conn.incr('counter')
      #     conn.get('key1')
      #   end
      #
      # @example Performance optimization
      #   # Instead of multiple round-trips:
      #   obj.save            # Round-trip 1
      #   obj.increment_count # Round-trip 2
      #   obj.update_timestamp # Round-trip 3
      #
      #   # Use pipeline for single round-trip:
      #   obj.pipelined do |conn|
      #     conn.hmset(obj.dbkey, obj.to_h)
      #     conn.hincrby(obj.dbkey, 'count', 1)
      #     conn.hset(obj.dbkey, 'updated_at', Familia.now.to_i)
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
      #   - Best for multiple independent operations
      #   - Reduces network latency by batching commands
      #   - Commands execute independently (some may succeed, others fail)
      #
      # @see Familia.pipelined For global pipeline method
      # @see MultiResult For details on the return value structure
      # @see #transaction For atomic command execution
      #
      def pipelined(&block)
        ensure_relatives_initialized! if respond_to?(:ensure_relatives_initialized!, true)
        Familia::Connection::PipelineCore.execute_pipeline(-> { dbclient }, &block)
      end

      # Alias for pipelined (alternate naming)
      def pipeline(&block)
        pipelined(&block)
      end
    end
  end
end
