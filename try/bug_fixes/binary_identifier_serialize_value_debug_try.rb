# try/bug_fixes/binary_identifier_serialize_value_debug_try.rb
#
# frozen_string_literal: true

# DataType#serialize_value stores a Familia record as its identifier. Its
# debug message put the record's class name next to the identifier and was
# built even with debug off, so for a class whose name holds non-ASCII
# text and an identifier given as BINARY with bytes that are not valid
# UTF-8, adding the record to a collection raised
# Encoding::CompatibilityError. save adds the record to the class's
# instances timeline the same way, so save of such a record raised too.
# With debug on, the trace before it raised the same way. The messages are
# now built only with debug on and show values through
# Familia.loggable_text.

require_relative '../support/helpers/test_helpers'
require 'stringio'

module ::Café
  class SerMember < Familia::Horreum
    prefix 'serdbg_member'
    identifier_field :mid
    field :mid
  end
end

class ::SerRoster < Familia::Horreum
  prefix 'serdbg_roster'
  identifier_field :rid
  field :rid
  set :people
end

# The prefix derives from the class name: :équipe_ser_dbg
class ::ÉquipeSerDbg < Familia::Horreum
  identifier_field :tid
  field :tid
  field :note
end

@cleanup = lambda do
  [Café::SerMember, SerRoster, ÉquipeSerDbg].each do |klass|
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

@roster = SerRoster.new(rid: 'r1')
@roster.save

## a collection adds a record of a non-ASCII class name with a BINARY identifier
@roster.people.add(Café::SerMember.new(mid: "bin\xFE".b))
@roster.people.members
#=> ["bin\xFE".b]

## save writes a record of a class whose prefix derives from a non-ASCII class name
ÉquipeSerDbg.new(tid: "bin\xFE".b, note: 'n').save
#=> true

## exists? and load find that record
[ÉquipeSerDbg.exists?("bin\xFE".b), ÉquipeSerDbg.load("bin\xFE".b)&.note]
#=> [true, 'n']

## its identifier is in the instances timeline
ÉquipeSerDbg.instances.members
#=> ["bin\xFE".b]

## with debug on, the collection adds the record and the log shows the identifier escaped
Familia.debug = true
begin
  @log_io.truncate(0)
  @roster.people.add(Café::SerMember.new(mid: "bîn\xFE".b))
  [@roster.people.members.include?("bîn\xFE".b), @log_io.string.include?('Café::SerMember => bîn\xFE')]
ensure
  Familia.debug = false
end
#=> [true, true]

## with debug on, save writes such a record
Familia.debug = true
begin
  ÉquipeSerDbg.new(tid: "bîn\xFE".b, note: 'd').save
ensure
  Familia.debug = false
end
#=> true

Familia.logger = @orig_logger
Familia.debug = @orig_debug
@cleanup.call
