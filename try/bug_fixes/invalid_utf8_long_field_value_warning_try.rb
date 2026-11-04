# try/bug_fixes/invalid_utf8_long_field_value_warning_try.rb
#
# frozen_string_literal: true

# validate_field_value warns when an indexed field value is longer than
# MAX_FIELD_VALUE_LENGTH and put the first characters of the value in the
# warning, next to a context that names the class. For a value given as
# BINARY with non-ASCII bytes, under a class whose name holds non-ASCII
# text, building the warning raised Encoding::CompatibilityError, so save
# wrote nothing. For a value with bytes that are not valid UTF-8, the
# warning wrote those bytes raw. The warning now shows the value through
# Familia.loggable_text.

require_relative '../support/helpers/test_helpers'
require 'stringio'

# The prefix derives from the class name: :équipe_long_value
class ::ÉquipeLongValue < Familia::Horreum
  feature :relationships

  identifier_field :uid
  field :uid
  field :role

  multi_index :role, :role_index
end

@cleanup = lambda do
  client = ÉquipeLongValue.dbclient
  keys = client.scan_each(match: "#{ÉquipeLongValue.prefix}:*").to_a
  client.del(*keys) unless keys.empty?
end
@cleanup.call

@orig_logger = Familia.logger
@log_io = StringIO.new
Familia.logger = Familia::FamiliaLogger.new(@log_io)

@invalid = "\xFE".b * 300
@valid_binary = ('é' * 200).b

## save writes a record whose long indexed value is BINARY and not valid UTF-8
ÉquipeLongValue.new(uid: 'l-1', role: @invalid).save
#=> true

## the index finds that record
ÉquipeLongValue.find_all_by_role(@invalid).map(&:uid)
#=> ['l-1']

## the loaded record saves again
ÉquipeLongValue.find_by_id('l-1').save
#=> true

## save writes a record whose long indexed value is BINARY with valid UTF-8 bytes
ÉquipeLongValue.new(uid: 'l-2', role: @valid_binary).save
#=> true

## the index finds that record too
ÉquipeLongValue.find_all_by_role(@valid_binary).map(&:uid)
#=> ['l-2']

## the warning shows the invalid bytes escaped and is valid UTF-8
@log_io.truncate(0)
@log_io.rewind
ÉquipeLongValue.new(uid: 'l-3', role: @invalid).save
warning = @log_io.string.lines.find { |line| line.include?('exceeds') }
[warning.include?('\xFE\xFE'), warning.b.include?("\xFE".b), warning.valid_encoding?]
#=> [true, false, true]

Familia.logger = @orig_logger
@cleanup.call
