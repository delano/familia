# try/bug_fixes/binary_dbkey_update_expiration_try.rb
#
# frozen_string_literal: true

# A key built from an identifier whose bytes are not valid UTF-8 is BINARY.
# save, commit_fields, save_fields and batch_update call update_expiration,
# whose debug message for a class without the expiration feature was built
# even with debug off and put the key next to the class name. For a class
# whose name holds non-ASCII text, such as Café::DbgOrder, that raised
# Encoding::CompatibilityError before anything was written.

require_relative '../support/helpers/test_helpers'
require 'stringio'

module ::Café
  class DbgOrder < Familia::Horreum
    prefix 'dbgexp_order'
    identifier_field :oid
    field :oid
    field :note
  end
end

@cleanup = lambda do
  [Café::DbgOrder].each do |klass|
    client = klass.dbclient
    keys = client.scan_each(match: "#{klass.prefix}:*").to_a
    client.del(*keys) unless keys.empty?
  end
end
@cleanup.call

@orig_logger = Familia.logger
@orig_debug = Familia.debug?
@log_io = StringIO.new
Familia.logger = Familia::FamiliaLogger.new(@log_io)
Familia.debug = false

## save writes a record of a non-ASCII class name whose identifier is not valid UTF-8
Café::DbgOrder.new(oid: "bad\xFF", note: 'x').save
#=> true

## the hash is stored
Café::DbgOrder.dbclient.hgetall("dbgexp_order:bad\xFF:object".b)
#=> { 'oid' => "\"bad\xFF\"".b, 'note' => '"x"' }

## commit_fields writes it too
order = Café::DbgOrder.new(oid: "bad\xFF")
order.note = 'y'
order.commit_fields.successful?
#=> true

## save_fields writes it too
order = Café::DbgOrder.new(oid: "bad\xFF")
order.note = 'z'
order.save_fields(:note)
Café::DbgOrder.find_by_id("bad\xFF").note
#=> 'z'

## with debug on, save writes the record and logs the key with the invalid byte escaped
Familia.debug = true
begin
  @log_io.truncate(0)
  [Café::DbgOrder.new(oid: "bad\xFF", note: 'd').save,
   @log_io.string.include?('Key: dbgexp_order:bad\xFF:object')]
ensure
  Familia.debug = false
end
#=> [true, true]

Familia.logger = @orig_logger
Familia.debug = @orig_debug
@cleanup.call
