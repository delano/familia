# lib/familia/connection.rb
#
# frozen_string_literal: true

require_relative 'connection/behavior'
require_relative 'connection/handlers'
require_relative 'connection/middleware'
require_relative 'connection/operations'
require_relative 'connection/individual_command_proxy'
require_relative 'connection/operation_core'
require_relative 'connection/transaction_core'
require_relative 'connection/pipelined_core'

# Familia
#
# A family warehouse for your keystore data.
#
module Familia
  @uri = URI.parse 'redis://127.0.0.1:6379'
  @middleware_registered = false
  @logger_registered = false
  @counter_registered = false
  @middleware_version = Concurrent::AtomicFixnum.new(0)
  @connection_chain_mutex = Familia::ThreadSafety::InstrumentedMutex.new('connection_chain')  # Thread-safe connection chain initialization

  # The Connection module provides Database connection management for Familia.
  # It allows easy setup and access to Database clients across different URIs
  # with robust connection pooling for thread safety.
  module Connection
    # @return [URI] The default URI for Database connections
    attr_reader :uri

    # @return [Proc] A callable that provides Database connections
    # The provider should accept a URI string and return a Redis connection
    # already connected to the correct database specified in the URI.
    #
    # ## Contract
    #
    # Familia calls the provider every time it needs a client and never hands
    # the connection back -- there is no check-in hook. The provider must
    # therefore return a client that remains exclusively usable by the caller
    # without a matching check-in.
    #
    # `pool.with { |conn| conn }` does NOT satisfy that contract: `with` checks
    # the connection back in the moment its block returns, so the client handed
    # to Familia is simultaneously available to every other checkout. Under
    # concurrency two threads end up issuing commands on one connection, and
    # per-connection state (MULTI, WATCH, SELECT, SUBSCRIBE) crosses callers.
    #
    # `ConnectionPool::Wrapper` (alias `ConnectionPool.wrap`) does satisfy it:
    # it proxies each command through `pool.with`, so a connection is checked
    # out for exactly the duration of that command and checked back in
    # afterwards. ConnectionPool's checkout is reentrant per fiber, so a
    # MULTI/EXEC, a pipeline, or a WATCH-guarded transaction still runs
    # entirely on one connection.
    #
    # Build the pool once, outside the lambda. A `ConnectionPool.new` inside
    # the provider mints a fresh pool -- and eventually a fresh connection --
    # on every call.
    #
    # @example Setting a connection provider
    #   require 'connection_pool'
    #
    #   POOLS = {}
    #   POOLS_MUTEX = Mutex.new
    #
    #   Familia.connection_provider = lambda do |uri|
    #     POOLS_MUTEX.synchronize do
    #       POOLS[uri] ||= ConnectionPool::Wrapper.new(size: 10, timeout: 5) do
    #         Redis.new(url: uri) # uri already carries the logical database
    #       end
    #     end
    #   end
    #
    # @example Holding one connection per unit of work
    #   # When a request should pin a single connection, check out in the
    #   # provider and check back in at the boundary. Without the check-in a
    #   # bare `checkout` leaks a connection per call and the pool exhausts.
    #   Familia.connection_provider = ->(uri) { POOLS.fetch(uri).checkout }
    #
    #   def call(env)  # Rack middleware / job wrapper
    #     @app.call(env)
    #   ensure
    #     POOLS.each_value { |pool| pool.checkin(force: true) }
    #   end
    #
    # @see docs/reference/api-technical.md#connection-provider-pattern
    attr_reader :connection_provider

    # Sets the connection provider and bumps middleware version
    def connection_provider=(provider)
      @connection_provider = provider
      increment_middleware_version! if provider
      @connection_chain = nil # Force rebuild of chain
    end

    # Sets the default URI for Database connections.
    #
    # NOTE: uri is not a property of the Settings module b/c it's not
    # configured in class defintions like default_expiration or logical DB index.
    #
    # @param uri [String, URI] The new default URI
    # @example Familia.uri = 'redis://localhost:6379'
    def uri=(uri)
      @uri = normalize_uri(uri)
    end
    alias url uri
    alias url= uri=

    # Creates a new Database connection instance.
    #
    # This method always creates a fresh connection and does not use caching.
    # Each call returns a new Redis client instance that you are responsible
    # for managing and closing when done.
    #
    # @param uri [String, URI, nil] The URI of the Database server to connect to.
    #   If nil, uses the default URI from Familia.uri.
    # @return [Redis] A new Database client connection.
    # @raise [ArgumentError] If no URI is specified.
    #
    # @example Creating a new connection
    #   client = Familia.create_dbclient('redis://localhost:6379')
    #   client.ping
    #   client.close
    #
    def create_dbclient(uri = nil)
      parsed_uri = normalize_uri(uri)

      # Register middleware only once, globally
      register_middleware_once

      Redis.new(parsed_uri.conf.merge(timeout: 5))
    end
    alias connect create_dbclient # backwards compatibility
    alias isolated_dbclient create_dbclient # matches with_isolated_dbclient api

    # Retrieves a Database connection using the Chain of Responsibility pattern.
    # Handles DB selection automatically based on the URI.
    #
    # Thread-safe: Uses double-checked locking pattern to avoid mutex overhead
    # on the hot path. Only acquires mutex during initial lazy initialization.
    # MRI's GIL provides implicit memory barriers making this pattern safe.
    #
    # @return [Redis] The Database client for the specified URI
    # @example Familia.dbclient('redis://localhost:6379/1')
    #   Familia.dbclient(2)  # Use DB 2 with default server
    def dbclient(uri = nil)
      # Fast path - read with local variable to ensure single read
      chain = @connection_chain
      return chain.handle(uri) if chain

      # Slow path - initialization only
      @connection_chain_mutex.synchronize do
        @connection_chain ||= build_connection_chain
      end.handle(uri)
    end

    # Builds the connection chain with handlers in priority order
    def build_connection_chain
      ResponsibilityChain.new
        .add_handler(Familia::Connection::FiberPipelineHandler.instance)
        .add_handler(Familia::Connection::FiberTransactionHandler.instance)
        .add_handler(FiberConnectionHandler.new)
        .add_handler(ProviderConnectionHandler.new)
        .add_handler(CreateConnectionHandler.new)
    end

    # Normalizes various URI formats to a consistent URI object
    # Made public so handlers can use it
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
        Familia.uri
      else
        raise ArgumentError, "Invalid URI type: #{uri.class.name}"
      end
    end

    # Extend self with submodules to make their methods available as module methods
    include Familia::Connection::Middleware
    include Familia::Connection::Operations
  end
end
