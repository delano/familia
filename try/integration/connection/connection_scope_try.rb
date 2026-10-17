# try/integration/connection/connection_scope_try.rb
#
# frozen_string_literal: true

# Connection Scope Tryouts (issue #456)
#
# Familia.with_connection_scope holds one client per distinct connection
# configuration for the duration of a block, owned by the fiber that opened
# it, and closes those clients when the block exits. These tests cover the
# acceptance criterion from issue #456 (bounded connection creation) and
# the documented semantics: cleanup on return and on exception, URI
# identity, transaction and pipeline affinity, model resolution, nesting,
# fiber ownership, provider and class-level @dbclient precedence, reset via
# reconnect!, released scopes, the Behavior-level API and fork.
#
# Identity is always checked through the server (CLIENT ID / CLIENT INFO),
# never through ObjectSpace or GC. Keys are namespaced with this file's
# name and removed with delete_test_dbkeys; nothing here flushes.

require_relative '../../support/helpers/test_helpers'

class ConnScopeTryWidget < Familia::Horreum
  prefix :connection_scope_try_widget
  identifier_field :wid
  field :wid
  field :name
  set :tags
  list :events
end

class ConnScopeTryGadget < Familia::Horreum
  prefix :connection_scope_try_gadget
  logical_database 2
  identifier_field :gid
  field :gid
  field :name
  set :tags
end

class ConnScopeTryCached < Familia::Horreum
  prefix :connection_scope_try_cached
  identifier_field :cid
  field :cid
end

def conn_scope_try_client_id(client)
  client.call('CLIENT', 'ID')
end

def conn_scope_try_client_db(client)
  client.call('CLIENT', 'INFO')[/\bdb=(\d+)/, 1]
end

# Redis#connected? returns nil (not false) once a client is closed, because
# it is `@client.connected? || @subscription_client&.connected?`. Normalize
# to a strict boolean so expectations read as open/closed.
def conn_scope_try_open?(client)
  client.connected? ? true : false
end

def conn_scope_try_cleanup
  Familia.with_connection_scope do
    delete_test_dbkeys(ConnScopeTryWidget, ConnScopeTryGadget, ConnScopeTryCached)
    delete_test_dbkeys('connection_scope_try:*', client: Familia.dbclient(1))
  end
end

# Scenarios 9 and 10 change globals the whole suite shares. Record the
# provider so it can be restored even if an earlier file left one set.
@conn_scope_try_original_provider = Familia.connection_provider
Familia.connection_provider = nil
conn_scope_try_cleanup

## Setup leaves no scope on the fiber
[Familia.current_connection_scope, Fiber[:familia_connection_scope]]
#=> [nil, nil]

## 1. Outside any scope, 100 lookups create 100 distinct server-side clients
@unscoped_clients = []
begin
  100.times { @unscoped_clients << Familia.dbclient }
  @unscoped_clients.map { |client| conn_scope_try_client_id(client) }.uniq.size
ensure
  @unscoped_clients.each(&:close)
end
#=> 100

## 1. Inside a scope, 100 lookups of the default URI share one server-side client
Familia.with_connection_scope do
  Array.new(100) { conn_scope_try_client_id(Familia.dbclient) }.uniq.size
end
#=> 1

## 1. The scope holds a single client after many lookups of the same URI
Familia.with_connection_scope do
  50.times { Familia.dbclient }
  50.times { Familia.dbclient(0) }
  Familia.current_connection_scope.size
end
#=> 1

## 2. Normal exit returns the block's value
@normal_client = nil
@normal_was_connected = nil
Familia.with_connection_scope do |client|
  @normal_client = client
  client.ping
  @normal_was_connected = conn_scope_try_open?(client)
  :block_value
end
#=> :block_value

## 2. Normal exit closes the yielded client
[@normal_was_connected, conn_scope_try_open?(@normal_client)]
#=> [true, false]

## 2. Normal exit leaves no scope on the fiber
[Familia.current_connection_scope, Fiber[:familia_connection_scope]]
#=> [nil, nil]

## 3. An exception inside the block propagates to the caller
@raised_client = nil
Familia.with_connection_scope do |client|
  @raised_client = client
  client.ping
  raise ArgumentError, 'connection_scope_try boom'
end
#=!> error.is_a?(ArgumentError) && error.message == 'connection_scope_try boom'

## 3. After the exception the client is closed and the scope is gone
[conn_scope_try_open?(@raised_client), Familia.current_connection_scope, Fiber[:familia_connection_scope]]
#=> [false, nil, nil]

## 4. Integer and String spellings of database 1 resolve to the same client
Familia.with_connection_scope do
  Familia.dbclient(1).equal?(Familia.dbclient('redis://127.0.0.1:2525/1'))
end
#=> true

## 4. nil and 0 resolve to the yielded default client
Familia.with_connection_scope do |client|
  [Familia.dbclient.equal?(client), Familia.dbclient(0).equal?(client)]
end
#=> [true, true]

## 4. The database 1 client is selected on database 1
Familia.with_connection_scope do
  conn_scope_try_client_db(Familia.dbclient(1))
end
#=> '1'

## 4. Two databases spelled four ways means exactly two clients
Familia.with_connection_scope do
  Familia.dbclient
  Familia.dbclient(0)
  Familia.dbclient(1)
  Familia.dbclient('redis://127.0.0.1:2525/1')
  Familia.current_connection_scope.size
end
#=> 2

## 4. A logical_database 2 model resolves to its own database 2 client
Familia.with_connection_scope do |db0|
  db2 = ConnScopeTryGadget.dbclient
  [db2.equal?(db0), conn_scope_try_client_db(db2), conn_scope_try_client_db(db0),
   Familia.current_connection_scope.size]
end
#=> [false, '2', '0', 2]

## 5. A transaction inside a scope runs on the scope's client
Familia.with_connection_scope do |client|
  result = Familia.transaction { |conn| conn.call('CLIENT', 'ID') }
  result.results.first == conn_scope_try_client_id(client)
end
#=> true

## 5. A pipeline inside a scope runs on the scope's client
Familia.with_connection_scope do |client|
  result = Familia.pipelined { |conn| conn.call('CLIENT', 'ID') }
  result.results.first == conn_scope_try_client_id(client)
end
#=> true

## 5. A plain lookup inside a scope is served by ScopedConnectionHandler
Familia.with_connection_scope do
  Familia.dbclient
  Fiber[:familia_connection_handler_class]
end
#=> Familia::Connection::ScopedConnectionHandler

## 5. A WATCH-guarded atomic_write inside a scope succeeds on the scope's client
Familia.with_connection_scope do |client|
  widget = ConnScopeTryWidget.new(wid: 'watched', name: 'before')
  ok = Familia.atomic_write(widget, watch_keys: [widget.dbkey]) do
    widget.name = 'after'
    widget.tags.add('watched')
  end
  reloaded = ConnScopeTryWidget.find_by_id('watched')
  [ok, widget.dbclient.equal?(client), reloaded.name, reloaded.tags.members,
   Familia.current_connection_scope.size]
end
#=> [true, true, 'after', ['watched'], 1]

## 6. A loop of model operations holds one client per logical database used
Familia.with_connection_scope do |db0|
  10.times do |i|
    widget = ConnScopeTryWidget.new(wid: "loop#{i}", name: "widget #{i}")
    widget.save
    widget.tags.add("t#{i}")
    widget.events.push("e#{i}")
    ConnScopeTryWidget.find_by_id("loop#{i}")
    gadget = ConnScopeTryGadget.new(gid: "loop#{i}", name: "gadget #{i}")
    gadget.save
    gadget.tags.add("t#{i}")
    ConnScopeTryGadget.find_by_id("loop#{i}")
  end
  [Familia.current_connection_scope.size,
   Familia.current_connection_scope.clients.map { |c| conn_scope_try_client_db(c) }.sort,
   ConnScopeTryWidget.dbclient.equal?(db0)]
end
#=> [2, ['0', '2'], true]

## 6. Class, instance and collection resolve to the same scope client
Familia.with_connection_scope do
  widget = ConnScopeTryWidget.find_by_id('loop0')
  gadget = ConnScopeTryGadget.find_by_id('loop0')
  db0 = ConnScopeTryWidget.dbclient
  db2 = ConnScopeTryGadget.dbclient
  [widget.dbclient.equal?(db0), widget.tags.dbclient.equal?(db0), widget.events.dbclient.equal?(db0),
   gadget.dbclient.equal?(db2), gadget.tags.dbclient.equal?(db2), db0.equal?(db2),
   widget.name, gadget.name]
end
#=> [true, true, true, true, true, false, 'widget 0', 'gadget 0']

## 7. An inner scope yields the outer scope's client and releases nothing
@outer_client = nil
Familia.with_connection_scope do |outer|
  @outer_client = outer
  inner_same = Familia.with_connection_scope do |inner|
    inner.ping
    inner.equal?(outer)
  end
  [inner_same, conn_scope_try_open?(outer), Familia.current_connection_scope.active?,
   Familia.current_connection_scope.size]
end
#=> [true, true, true, 1]

## 7. The client closes only after the outer block exits
[conn_scope_try_open?(@outer_client), Familia.current_connection_scope]
#=> [false, nil]

## 7. An exception in a joined inner block leaves the outer scope active
@outer_after_inner_error = nil
Familia.with_connection_scope do |outer|
  outer.ping
  begin
    Familia.with_connection_scope { raise ArgumentError, 'inner' }
  rescue ArgumentError => e
    @outer_after_inner_error = [e.message, Familia.current_connection_scope.active?,
                                conn_scope_try_open?(outer), Familia.dbclient.equal?(outer)]
  end
  @outer_after_inner_error
end
#=> ['inner', true, true, true]

## 8. A thread spawned inside the block does not see the scope
Familia.with_connection_scope do |client|
  owner_id = conn_scope_try_client_id(client)
  saw_scope, thread_id = Thread.new do
    thread_client = Familia.dbclient
    begin
      [!Familia.current_connection_scope.nil?, conn_scope_try_client_id(thread_client)]
    ensure
      thread_client.close
    end
  end.value
  [saw_scope, thread_id == owner_id]
end
#=> [false, false]

## 8. A fiber resumed inside the block does not see the scope
Familia.with_connection_scope do |client|
  owner_id = conn_scope_try_client_id(client)
  saw_scope, fiber_id = Fiber.new do
    fiber_client = Familia.dbclient
    begin
      [!Familia.current_connection_scope.nil?, conn_scope_try_client_id(fiber_client)]
    ensure
      fiber_client.close
    end
  end.resume
  [saw_scope, fiber_id == owner_id]
end
#=> [false, false]

## 8. Another thread cannot borrow the scope's clients
Familia.with_connection_scope do
  scope = Familia.current_connection_scope
  Thread.new do
    scope.client(Familia.uri)
    :no_error
  rescue Familia::Problem => e
    e.class
  end.value
end
#=> Familia::Problem

## 8. Another thread cannot release the scope
Familia.with_connection_scope do |client|
  client.ping
  scope = Familia.current_connection_scope
  outcome = Thread.new do
    scope.release!
    :no_error
  rescue Familia::Problem => e
    e.class
  end.value
  [outcome, scope.active?, conn_scope_try_open?(client)]
end
#=> [Familia::Problem, true, true]

## 9. A configured connection_provider takes precedence over the scope
@provider_client = Redis.new(url: 'redis://127.0.0.1:2525/0')
begin
  Familia.connection_provider = ->(_uri) { @provider_client }
  Familia.with_connection_scope do |client|
    [client.equal?(@provider_client), Familia.current_connection_scope.size,
     Fiber[:familia_connection_handler_class]]
  end
ensure
  Familia.connection_provider = nil
  @provider_client.close
end
#=> [true, 0, Familia::Connection::ProviderConnectionHandler]

## 9. A class-level @dbclient keeps serving inside a scope
@cached_client = Redis.new(url: 'redis://127.0.0.1:2525/0')
begin
  ConnScopeTryCached.dbclient = @cached_client
  Familia.with_connection_scope do |scope_client|
    [ConnScopeTryCached.dbclient.equal?(@cached_client),
     ConnScopeTryCached.dbclient.equal?(scope_client),
     Familia.current_connection_scope.size]
  end
ensure
  ConnScopeTryCached.dbclient = nil
  @cached_client.close
end
#=> [true, false, 1]

## 10. reconnect! inside a scope retires the held client and serves a fresh one
@retired_client = nil
@fresh_client = nil
Familia.with_connection_scope do |before|
  before.ping
  Familia.reconnect!
  after = Familia.dbclient
  after.ping
  @retired_client = before
  @fresh_client = after
  [after.equal?(before), conn_scope_try_open?(before), conn_scope_try_open?(after),
   Familia.current_connection_scope.middleware_version == Familia.middleware_version,
   Familia.current_connection_scope.size,
   Familia.current_connection_scope.clients == [before, after]]
end
#=> [false, true, true, true, 2, true]

## 10. Retired and fresh clients are both closed when the block exits
[conn_scope_try_open?(@retired_client), conn_scope_try_open?(@fresh_client)]
#=> [false, false]

## 10. A version bump inside a WATCH window does not drop the WATCH
# A concurrent writer touches the watched key between WATCH and MULTI while
# pre_check bumps the middleware version and makes a lookup. The scope keeps
# the WATCHing client open, so EXEC aborts on every attempt and the
# optimistic lock holds.
@watched = ConnScopeTryWidget.new(wid: 'watch_bump')
@watched.name = 'original'
@watched.save
@intruder_client = Redis.new(url: 'redis://127.0.0.1:2525/0')
begin
  Familia.with_connection_scope do
    @watched.name = 'mine'
    Familia.atomic_write(@watched, watch_keys: [@watched.dbkey], pre_check: lambda {
      @intruder_client.hset(@watched.dbkey, 'name', '"intruder"')
      Familia.reconnect!
      Familia.dbclient.ping
    })
  end
ensure
  @intruder_client.close
end
#=!> Familia::OptimisticLockError

## 10. The concurrent write survives the aborted transaction
ConnScopeTryWidget.load('watch_bump').name
#=> 'intruder'

## 11. A released scope rejects lookups
@released_scope = Familia.with_connection_scope { Familia.current_connection_scope }
@released_scope.client(Familia.uri)
#=!> error.is_a?(Familia::Problem) && error.message == 'Connection scope has been released'

## 11. release! is idempotent and the scope reports released
[@released_scope.release!, @released_scope.release!, @released_scope.released?,
 @released_scope.active?, @released_scope.size]
#=> [nil, nil, true, false, 0]

## 12. Model.with_connection_scope yields the model's client on its logical database
ConnScopeTryGadget.with_connection_scope do |client|
  [ConnScopeTryGadget.dbclient.equal?(client), conn_scope_try_client_db(client),
   Familia.current_connection_scope.size]
end
#=> [true, '2', 1]

## 12. A standalone DataType resolves to the scope's client for its database
Familia.with_connection_scope(1) do |db1|
  hk = Familia::HashKey.new('connection_scope_try:standalone', logical_database: 1)
  hk['k'] = 'v'
  [hk.dbclient.equal?(db1), hk.dbclient.equal?(Familia.dbclient(1)),
   conn_scope_try_client_db(hk.dbclient), hk['k'], Familia.current_connection_scope.size]
end
#=> [true, true, '1', 'v', 1]

## 13. A forked child inherits the scope and talks on its own socket
Familia.with_connection_scope do |client|
  parent_id = conn_scope_try_client_id(client)
  if Process.respond_to?(:fork)
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      writer.puts Familia.dbclient.call('CLIENT', 'ID')
      writer.puts Familia.current_connection_scope.nil?
      writer.close
      exit!(0)
    end
    writer.close
    child_id, child_without_scope = reader.read.split
    reader.close
    Process.wait(pid)
    [child_id.to_i != parent_id, child_without_scope == 'false', client.ping]
  else
    [true, true, 'PONG']
  end
end
#=> [true, true, 'PONG']

# Teardown
conn_scope_try_cleanup
Familia.connection_provider = @conn_scope_try_original_provider
