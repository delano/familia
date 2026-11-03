# lib/familia/connection.rb
#
# frozen_string_literal: true

require_relative 'connection/behavior'
require_relative 'connection/scope'
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
    # Resolution order: an active pipeline or transaction connection, a
    # fiber-local connection, the {#connection_provider}, the client held by
    # an open {#with_connection_scope}, and finally {CreateConnectionHandler}.
    #
    # ## Cost of the fallback
    #
    # With no provider and no open scope, every call that reaches the
    # fallback returns a new `Redis` client. The client connects lazily, on
    # its first command, and nothing closes it: each lookup that goes on to
    # issue a command costs a TCP connection that stays open until the client
    # is garbage collected, and the socket lingers in TIME_WAIT after that. A
    # loop that calls `dbclient` per iteration therefore creates one
    # connection per iteration. That default is kept on purpose, so a bare
    # `Familia.dbclient` in a console or script keeps working with no setup.
    #
    # Code that issues more than a handful of commands should hold a
    # connection instead:
    #
    # - A request, job, script or test: wrap the unit of work in
    #   {#with_connection_scope}. Lookups inside the block share one client
    #   per URI and the clients are closed when the block exits.
    # - A long-running, multi-threaded process: configure a pooled
    #   {#connection_provider}; the scope steps aside when a provider is set.
    #
    # Thread-safe: Uses double-checked locking pattern to avoid mutex overhead
    # on the hot path. Only acquires mutex during initial lazy initialization.
    # MRI's GIL provides implicit memory barriers making this pattern safe.
    #
    # @return [Redis] The Database client for the specified URI
    # @example Familia.dbclient('redis://localhost:6379/1')
    #   Familia.dbclient(2)  # Use DB 2 with default server
    # @see #with_connection_scope
    def dbclient(uri = nil)
      # Fast path - read with local variable to ensure single read
      chain = @connection_chain
      return chain.handle(uri) if chain

      # Slow path - initialization only
      @connection_chain_mutex.synchronize do
        @connection_chain ||= build_connection_chain
      end.handle(uri)
    end

    # Runs the block inside a connection scope owned by the current fiber.
    #
    # While the block runs, every `dbclient` lookup in this fiber that would
    # otherwise create a fresh client (no {#connection_provider}, no
    # class-level `@dbclient`) resolves to one client per distinct connection
    # configuration, held by the scope. When the block exits, by return or by
    # exception, the scope closes every client it created. This bounds
    # connection creation to one per URI per scope, however many lookups the
    # block performs.
    #
    # The block receives the scope's client for `uri` (the default URI when
    # nil), resolved through {#dbclient}; inside an open transaction or
    # pipeline that is the transaction or pipeline connection.
    #
    # ## Semantics
    #
    # - **Nesting**: a scope opened inside an active scope of the same fiber
    #   joins it. Nothing is acquired or released until the outer block exits.
    # - **Transactions and pipelines**: `transaction`, `pipelined`,
    #   `atomic_write` and WATCH-guarded writes inside the block run on the
    #   scope's client for their URI, so the commands of one operation share
    #   one socket.
    # - **Ownership**: the scope belongs to the fiber that opened it. Threads
    #   and fibers spawned inside the block inherit a copy of fiber storage
    #   but are not the owner, so they do not see the scope and resolve
    #   connections as if none were open. Open a scope in each thread or
    #   fiber that needs one.
    # - **Providers and class-level clients**: a fiber-local connection set
    #   with {#fiber_connection=}, a configured {#connection_provider} and a
    #   class `@dbclient` take precedence over the scope, which then holds
    #   nothing for those lookups.
    # - **Fork**: a client created before `fork` is a `Redis` object whose
    #   underlying `RedisClient` closes an inherited socket and reconnects
    #   when it notices the process id changed, so a scope that spans a fork
    #   keeps working in the child on the child's own sockets. The parent's
    #   sockets are not affected. Opening the scope after the fork avoids the
    #   question.
    # - **Reset**: `Familia.reconnect!` and the setters that bump
    #   `middleware_version` make the scope retire its clients on the next
    #   lookup: new lookups get fresh clients, and the retired ones stay open
    #   until the block exits so a handle the block holds, or a WATCH in
    #   flight on it, keeps its connection. {#current_connection_scope}
    #   exposes the scope for inspection and an explicit {Scope#release!},
    #   which releases it for the rest of the block. After it, plain lookups
    #   resolve as if no scope were open, and a +with_connection_scope+
    #   opened later in the block opens a new scope of its own.
    # - **Limits**: a client reference kept past the block reconnects on its
    #   next command as an unowned connection. `Enumerator#next` runs its
    #   enumerator in a fiber of its own, so lookups made there resolve as if
    #   no scope were open. Per-connection state set on a scope client
    #   (SELECT, CLIENT SETNAME, SUBSCRIBE) is visible to every later lookup
    #   for that URI in the block.
    #
    # @param uri [String, URI, Integer, nil] URI or database number for the
    #   yielded client
    # @yield [Redis] the scope's client for `uri`
    # @return [Object] the block's return value
    #
    # @example Bounded connections for a job
    #   Familia.with_connection_scope do
    #     ids.each do |id|
    #       customer = Customer.load(id)
    #       customer.plan = 'premium'
    #       customer.save
    #     end
    #   end
    #   # One connection per logical database was opened, and all are closed.
    #
    # @example Rack middleware
    #   def call(env)
    #     Familia.with_connection_scope { @app.call(env) }
    #   end
    #
    # @see Familia::Connection::Scope
    # @see Familia::Connection::ScopedConnectionHandler
    def with_connection_scope(uri = nil)
      Familia::Connection::Scope.open { yield dbclient(uri) }
    end

    # The connection scope the current fiber has open, or nil.
    #
    # @return [Familia::Connection::Scope, nil]
    def current_connection_scope
      Familia::Connection::Scope.current
    end

    # Builds the connection chain with handlers in priority order
    def build_connection_chain
      ResponsibilityChain.new
        .add_handler(Familia::Connection::FiberPipelineHandler.instance)
        .add_handler(Familia::Connection::FiberTransactionHandler.instance)
        .add_handler(FiberConnectionHandler.new)
        .add_handler(ProviderConnectionHandler.new)
        .add_handler(ScopedConnectionHandler.new)
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
