# try/integration/futures/conditional_write_scripting_try.rb
#
# frozen_string_literal: true

# Inside a transaction or pipeline, HashKey#hsetnx, ListKey#insert,
# JsonStringKey#setnx and JsonStringKey#value with a default queue an EVAL,
# so they need scripting permission there. These testcases connect as an
# ACL user without @scripting: outside a block the same calls send plain
# HSETNX, LINSERT and SETNX and work, while inside a block the server
# refuses the EVAL with NOPERM.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

class ScriptlessAccount < Familia::Horreum
  feature :expiration
  default_expiration 3600
  identifier_field :acctid
  field :acctid
  hashkey :attrs
  list :items
  json_string :settings, default: { 'theme' => 'light' }
end

@admin = Familia.create_dbclient
@admin.call('ACL', 'SETUSER', 'familia_scriptless', 'on', '>scriptless', '~*', '+@all', '-@scripting')

@original_provider = Familia.connection_provider
@scriptless_clients = {}
Familia.connection_provider = lambda do |uri|
  @scriptless_clients[uri.to_s] ||= Redis.new(url: uri.to_s, username: 'familia_scriptless', password: 'scriptless')
end

delete_test_dbkeys(ScriptlessAccount, client: @admin)

@acct = ScriptlessAccount.new(acctid: 'scriptless-1')
@acct.save
@acct.items.push('a')

## the test user cannot run EVAL
begin
  ScriptlessAccount.dbclient.call(:eval, 'return 1', 0)
rescue Redis::PermissionError => e
  e.message.start_with?('NOPERM')
end
#=> true

## outside a block: hsetnx, insert, setnx and #value with a default work without scripting
[
  @acct.attrs.hsetnx('plain', 1),
  @acct.items.insert(:before, 'a', 'b'),
  @acct.settings.value,
  @acct.settings.setnx({ 'theme' => 'dark' }),
]
#=> [true, 2, {"theme"=>"light"}, false]

## inside a transaction: hsetnx raises Redis::PermissionError
Familia.transaction do
  @acct.attrs['before'] = 1
  @acct.attrs.hsetnx('queued', 2)
end
#=!> Redis::PermissionError

## inside a transaction: the refused EVAL aborts the other queued writes too
@admin.hgetall(@acct.attrs.dbkey).keys.sort
#=> ["plain"]

## inside a transaction: a json_string read with a default raises Redis::PermissionError
Familia.transaction do
  @acct.attrs['before'] = 1
  @acct.settings.value
end
#=!> Redis::PermissionError

## inside atomic_write: insert raises Redis::PermissionError and the list is unchanged
begin
  @acct.atomic_write { @acct.items.insert(:after, 'a', 'c') }
rescue Redis::PermissionError
  @acct.items.to_a
end
#=> ["b", "a"]

## inside a pipeline: setnx raises Redis::PermissionError after the pipeline runs
Familia.pipelined do
  @acct.attrs['piped'] = 1
  @acct.settings.setnx({ 'theme' => 'dark' })
end
#=!> Redis::PermissionError

## inside a pipeline: the other commands were not atomic with the EVAL and did run
@admin.hgetall(@acct.attrs.dbkey).keys.sort
#=> ["piped", "plain"]

# Teardown
Familia.connection_provider = @original_provider
@scriptless_clients.each_value(&:close)
delete_test_dbkeys(ScriptlessAccount, client: @admin)
@admin.call('ACL', 'DELUSER', 'familia_scriptless')
@admin.close
