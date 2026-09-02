# try/edge_cases/legacy_data_detection/find_by_id_legacy_string_try.rb
#
# frozen_string_literal: true

# Regression: loading a record whose stored hash contains a non-JSON field
# value (a "legacy plain string", e.g. written by a pre-JSON serializer or by
# hand via HSET) must not raise Familia::NoIdentifier.
#
# During instantiate_from_hash the instance is allocated and every field is
# deserialized before any setter runs, so the identifier is still nil when
# log_deserialization_issue tries to compute dbkey for the log message.
# refresh! never hit this because the instance already had its identifier.

require_relative '../../support/helpers/test_helpers'
require 'logger'
require 'stringio'

# Model with a field that holds a hand-written non-JSON value.
class LegacyStringFinder < Familia::Horreum
  identifier_field :id
  field :id
  field :plain
  field :count
end

@key = LegacyStringFinder.dbkey('leg')
LegacyStringFinder.dbclient.del(@key)
LegacyStringFinder.dbclient.hset(@key, 'id', '"leg"')
LegacyStringFinder.dbclient.hset(@key, 'plain', 'legacy-plain-string') # not JSON
LegacyStringFinder.dbclient.hset(@key, 'count', '42')

@log_output = StringIO.new
@original_logger = Familia.instance_variable_get(:@logger)
Familia.instance_variable_set(:@logger, Logger.new(@log_output))
Familia.instance_variable_get(:@logger).level = Logger::DEBUG

## find_by_id does not raise on a hash with a non-JSON string field
@record = LegacyStringFinder.find_by_id('leg')
@record.class
#=> LegacyStringFinder

## The legacy field loads with the raw string as its value
@record.plain
#=> "legacy-plain-string"

## Sibling JSON fields still deserialize normally
[@record.id, @record.count]
#=> ["leg", 42]

## The identifier is intact after loading
@record.identifier
#=> "leg"

## The legacy string is logged with the intended message
@log_output.rewind
@log_output.read
#=~> /Legacy plain string in .*LegacyStringFinder#plain: "legacy-plain-string" \(no dbkey\)/

## find_by_dbkey follows the same path and also loads
LegacyStringFinder.find_by_dbkey(@key).plain
#=> "legacy-plain-string"

## load_multi (pipelined HGETALL) also loads the record
LegacyStringFinder.load_multi(['leg']).map(&:plain)
#=> ["legacy-plain-string"]

## refresh! on an instance that already has its identifier reports the dbkey
@log_output.truncate(0)
@log_output.rewind
@record.refresh!
@log_output.rewind
@log_output.read
#=~> /Legacy plain string in .*LegacyStringFinder#plain: "legacy-plain-string" \(legacy_string_finder:leg:object\)/

Familia.instance_variable_set(:@logger, @original_logger)
LegacyStringFinder.dbclient.del(@key)
