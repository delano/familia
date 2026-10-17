# lib/familia/connection/scope.rb
#
# frozen_string_literal: true

module Familia
  module Connection
    # A fiber-owned set of database connections held open for the duration
    # of a {Familia::Connection#with_connection_scope} block.
    #
    # Without a connection provider, every `dbclient` lookup that reaches
    # {CreateConnectionHandler} returns a new `Redis` client that nobody
    # closes. A scope gives those lookups an owner: while the block runs,
    # {ScopedConnectionHandler} resolves each lookup to the one client the
    # scope holds for that connection configuration, creating it on first
    # use, and {#release!} closes every client the scope created when the
    # block exits, on a normal return and on an exception alike.
    #
    # ## Ownership
    #
    # A scope belongs to the fiber that opened it. A new fiber starts with a
    # copy of the opener's fiber storage (Ruby's documentation for
    # `Fiber.new`: "If the storage is unspecified, the default is to inherit
    # a copy of the storage from the current fiber."), and a new thread's
    # root fiber does the same on Ruby 3.3 (observed; the Thread
    # documentation does not state it). A thread or fiber spawned inside the
    # block therefore sees the same `Fiber[FIBER_KEY]` value, but {.current}
    # and {#active?} compare the owner with `Fiber.current`, so those
    # children never share the owner's clients and resolve connections as if
    # no scope were open. They open their own scope when they need one.
    #
    # ## Identity of a connection
    #
    # Clients are keyed by the connection parameters the URI resolves to
    # (`URI#conf`: host, port, database, TLS, credentials, timeout). Two
    # lookups that differ only in how the URI is spelled, such as
    # `redis://host:6379` and `redis://host:6379/0`, share one client; a
    # different logical database or server gets its own.
    #
    # ## Nesting and operation modes
    #
    # Opening a scope inside an active scope of the same fiber joins it:
    # nothing new is acquired and nothing is released until the outer block
    # exits. An explicit {#release!} from anywhere inside the block, a joined
    # inner block included, releases the scope for the rest of the outer
    # block: plain lookups after it resolve as if no scope were open, and a
    # with_connection_scope opened after it opens a new scope of its own,
    # closed when that inner block exits. Transactions and pipelines
    # opened inside a scope run on the scope's client for their URI, because
    # the fiber-local transaction and pipeline handlers take precedence while
    # a block is open and then hand back to the scope.
    #
    # ## Reset
    #
    # `Familia.reconnect!` and the other calls that bump
    # `Familia.middleware_version` do not reach into other fibers. A scope
    # notices the new version on its next lookup and retires the clients it
    # created under the old version: new lookups get fresh clients, while the
    # retired ones stay open, so a handle the block already holds and a
    # WATCH or MULTI in flight on it keep their connection. Retired clients
    # are closed with the rest when the scope is released. Closing them at
    # once would let the `Redis` object reconnect silently on its next
    # command, dropping the WATCH.
    #
    # ## Limits
    #
    # - A client reference kept past the block reconnects on its next
    #   command, as an unowned connection that nothing closes.
    # - `Enumerator#next` and `#peek` run the enumerator in a fiber of their
    #   own, so lookups made there are not the owner's and resolve as if no
    #   scope were open.
    # - The scope's client for a URI is shared by every lookup for that URI
    #   in the block, so per-connection state set on it (SELECT, CLIENT
    #   SETNAME, SUBSCRIBE) is visible to the next lookup.
    #
    # @see Familia::Connection#with_connection_scope
    # @see Familia::Connection::ScopedConnectionHandler
    class Scope
      # Fiber storage key that holds the scope a fiber opened.
      FIBER_KEY = :familia_connection_scope

      class << self
        # The scope the current fiber opened and has not released yet.
        #
        # Returns nil outside a scope, after {#release!}, and in a thread or
        # fiber that inherited another fiber's scope through fiber storage.
        #
        # @return [Scope, nil]
        def current
          scope = Fiber[FIBER_KEY]
          scope if scope&.active?
        end

        # Runs the block inside a scope owned by the current fiber.
        #
        # Joins the active scope when one is open (reentrant). Otherwise
        # opens a new scope, restores the previous fiber storage value and
        # releases the scope when the block exits, whether it returns or
        # raises.
        #
        # @yield []
        # @return [Object] the block's return value
        def open
          return yield if current

          scope = new
          previous = Fiber[FIBER_KEY]
          Fiber[FIBER_KEY] = scope
          begin
            yield
          ensure
            Fiber[FIBER_KEY] = previous
            scope.release!
          end
        end
      end

      # @return [Fiber] the fiber that opened this scope
      attr_reader :owner

      # @return [Integer] the `Familia.middleware_version` the held clients were created under
      attr_reader :middleware_version

      def initialize
        @owner = Fiber.current
        @middleware_version = Familia.middleware_version
        @clients = {}
        @retired = []
        @released = false
      end

      # @return [Boolean] whether the current fiber is the one that opened this scope
      def owned_by_current_fiber?
        @owner.equal?(Fiber.current)
      end

      # @return [Boolean] whether {#release!} has run
      def released?
        @released
      end

      # @return [Boolean] true while the owning fiber can use this scope
      def active?
        !@released && owned_by_current_fiber?
      end

      # Returns the client this scope holds for `uri`, creating it on first
      # use with `Familia.create_dbclient`.
      #
      # @param uri [URI] a normalized URI (see `Familia.normalize_uri`)
      # @return [Redis]
      # @raise [Familia::Problem] when the scope has been released or
      #   belongs to another fiber
      def client(uri)
        raise Familia::Problem, 'Connection scope has been released' if @released
        raise Familia::Problem, 'Connection scope belongs to another fiber' unless owned_by_current_fiber?

        retire_stale_clients!
        @clients[uri.conf] ||= acquire(uri)
      end

      # @return [Array<Redis>] every client the scope holds open, retired
      #   ones first, then the current ones in acquisition order
      def clients
        (@retired + @clients.values).freeze
      end

      # @return [Integer] number of clients the scope holds open
      def size
        @retired.size + @clients.size
      end

      # Closes every client the scope holds and marks the scope released.
      # Further {#client} calls raise. Safe to call more than once; only the
      # owning fiber may call it.
      #
      # @return [nil]
      # @raise [Familia::Problem] when called from a fiber other than the owner
      def release!
        raise Familia::Problem, 'Connection scope belongs to another fiber' unless owned_by_current_fiber?

        @released = true
        close_all!
        nil
      end

      # Omits the held clients' connection parameters, which can carry a
      # password.
      #
      # @return [String]
      def inspect
        "#<#{self.class.name} clients=#{size} released=#{@released}>"
      end

      private

      def acquire(uri)
        client = Familia.create_dbclient(uri)
        Familia.trace :DBCLIENT_SCOPE, nil, "Scope created connection for #{uri.serverid}"
        client
      end

      # Clients created before a middleware version bump may lack middleware
      # registered since (see Familia.reconnect!). Retire them so new lookups
      # get fresh clients; they stay open until {#release!} because a handle
      # the block holds, or a WATCH in flight on it, must keep its connection.
      def retire_stale_clients!
        current = Familia.middleware_version
        return if current == @middleware_version

        @retired.concat(@clients.values)
        @clients = {}
        @middleware_version = current
      end

      # Closes every held client and forgets them.
      def close_all!
        pending = @retired + @clients.values
        @retired = []
        @clients = {}
        close_each(pending)
      end

      # Closes each client in turn, in one loop however many there are (a
      # long scope that retires clients on every version bump can hold
      # thousands). A StandardError from one close is logged and skipped.
      # Any other exception (an Interrupt or a Thread#raise timeout arriving
      # mid-close) is held until every client has been closed, and then the
      # first one is raised.
      def close_each(clients)
        interrupted = nil
        clients.each do |client|
          client.close
        rescue StandardError => e
          Familia.trace :DBCLIENT_SCOPE, nil, "Ignoring #{e.class} while closing scoped connection: #{e.message}"
        # Held, not swallowed: it is raised below once the loop has closed
        # the remaining clients.
        rescue Exception => e # rubocop:disable Lint/RescueException
          interrupted ||= e
        end
        raise interrupted if interrupted
      end
    end
  end
end
