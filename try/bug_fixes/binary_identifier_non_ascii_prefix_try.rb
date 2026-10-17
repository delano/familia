# try/bug_fixes/binary_identifier_non_ascii_prefix_try.rb
#
# frozen_string_literal: true

# redis-client returns a key or member as a BINARY (ASCII-8BIT) String when
# its bytes are not valid UTF-8. With a non-ASCII class prefix such as
# 'équipe', building a key from such an identifier raised
# Encoding::CompatibilityError: Familia.join (Array#join) could not combine
# the UTF-8 prefix with the BINARY identifier, and
# extract_identifier_from_key could not compare a BINARY key with the UTF-8
# prefix. Both now work on bytes, so exists?, load and rebuild_instances
# work for such a record.
#
# A key also had two String values: built from the UTF-8 identifier the
# record was saved with it was UTF-8, built from the member read back it was
# BINARY, and the two were neither == nor equal as Hash keys. Familia.join
# now returns every key in the encoding redis-client gives the same bytes
# (Familia.normalize_key_encoding): UTF-8 when valid, BINARY otherwise.

require_relative '../support/helpers/test_helpers'

class ::BinaryIdTeam < Familia::Horreum
  prefix 'équipe'
  identifier_field :tid
  field :tid
  field :name
end

@cleanup = lambda do
  client = BinaryIdTeam.dbclient
  keys = client.scan_each(match: 'équipe:*').to_a
  client.del(*keys) unless keys.empty?
end
@cleanup.call

@team = BinaryIdTeam.new(tid: "bad\xFF", name: 'Les Bleus')
@team.save
@member = BinaryIdTeam.instances.members.first
@stored_key = BinaryIdTeam.dbclient.scan_each(match: BinaryIdTeam.scan_pattern).first

## Familia.join keeps the result for ordinary UTF-8 parts
joined = Familia.join('équipe', 'alice', 'object')
[joined, joined.encoding]
#=> ['équipe:alice:object', Encoding::UTF_8]

## Familia.join joins incompatible parts as bytes and returns BINARY
joined = Familia.join('équipe', "bad\xFF".b, 'object')
[joined == "équipe:bad\xFF:object".b, joined.encoding]
#=> [true, Encoding::BINARY]

## the byte fallback flattens nested arrays and converts symbols like Array#join
Familia.join(['équipe', "bad\xFF".b], :object) == "équipe:bad\xFF:object".b
#=> true

## Familia.join returns one String value for a key, from the UTF-8 identifier or from the BINARY member
from_literal = Familia.join('équipe', "bad\xFF", 'object')
from_member = Familia.join('équipe', "bad\xFF".b, 'object')
[from_literal == from_member, from_literal.encoding, { from_member => 1 }[from_literal]]
#=> [true, Encoding::BINARY, 1]

## Familia.join returns UTF-8 when a BINARY part holds valid UTF-8 bytes
joined = Familia.join('user', 'élodie'.b, 'object')
[joined == 'user:élodie:object', joined.encoding]
#=> [true, Encoding::UTF_8]

## Familia.normalize_key_encoding relabels the bytes and leaves them unchanged
relabeled = [Familia.normalize_key_encoding('équipe'.b), Familia.normalize_key_encoding("bad\xFF")]
[relabeled.map(&:encoding), relabeled.map(&:b)]
#=> [[Encoding::UTF_8, Encoding::BINARY], ['équipe'.b, "bad\xFF".b]]

## DatabaseLogger renders mixed-encoding arguments as UTF-8 with escaped bytes
logged = DatabaseLogger.command_string(['ZADD', 'équipe:instances', '1', "bad\xFF".b], :call)
[logged, logged.encoding]
#=> ['ZADD équipe:instances 1 bad\xFF', Encoding::UTF_8]

## DatabaseLogger does the same for a pipeline
DatabaseLogger.command_string([['EXISTS', 'équipe:x'], ['ZADD', 'équipe:instances', '1', "bad\xFF".b]], :pipeline)
#=> 'EXISTS équipe:x | ZADD équipe:instances 1 bad\xFF'

## DatabaseLogger renders a lone BINARY argument as UTF-8 that CommandMessage can format
logged = DatabaseLogger.command_string(['EXISTS', "équipe:bad\xFF:object".b], :call)
message = DatabaseLogger::CommandMessage.new(logged, 1, 0.0)
[logged, logged.encoding, message.inspect.end_with?('> EXISTS équipe:bad\xFF:object')]
#=> ['EXISTS équipe:bad\xFF:object', Encoding::UTF_8, true]

## DatabaseLogger leaves ordinary commands unchanged
logged = DatabaseLogger.command_string(['HGET', 'équipe:alice:object', 'name'], :call)
[logged, logged.encoding]
#=> ['HGET équipe:alice:object name', Encoding::UTF_8]

## DatabaseLogger escapes invalid bytes in a UTF-8 argument, which a JSON log sink could not encode
logged = DatabaseLogger.command_string(['EXISTS', "équipe:bad\xFF:object"], :call)
[logged, logged.valid_encoding?]
#=> ['EXISTS équipe:bad\xFF:object', true]

## the instances member comes back from redis-rb as BINARY
[@member == "bad\xFF".b, @member.encoding]
#=> [true, Encoding::BINARY]

## dbkey built from the BINARY member has the stored key's bytes
BinaryIdTeam.dbkey(@member).b == @stored_key.b
#=> true

## dbkey from the saved record and from the BINARY member is the stored key, as one String value
[@team.dbkey == @stored_key, BinaryIdTeam.dbkey(@member) == @stored_key, @stored_key.encoding]
#=> [true, true, Encoding::BINARY]

## extract_identifier_from_key returns the identifier in the key's encoding
id = BinaryIdTeam.extract_identifier_from_key(@stored_key)
[id == "bad\xFF".b, id.encoding == @stored_key.encoding]
#=> [true, true]

## exists? finds the record from the BINARY member
BinaryIdTeam.exists?(@member)
#=> true

## load returns the record from the BINARY member
loaded = BinaryIdTeam.load(@member)
[loaded.tid.b, loaded.name]
#=> ["bad\xFF".b, 'Les Bleus']

## exists? and load also work with the default (unstructured) command log format
structured = DatabaseLogger.structured_logging
DatabaseLogger.structured_logging = false
begin
  [BinaryIdTeam.exists?(@member), BinaryIdTeam.load(@member).name]
ensure
  DatabaseLogger.structured_logging = structured
end
#=> [true, 'Les Bleus']

## rebuild_instances restores the timeline entry for the record
BinaryIdTeam.instances.clear
count = BinaryIdTeam.rebuild_instances
[count, BinaryIdTeam.instances.members.map(&:b)]
#=> [1, ["bad\xFF".b]]

@cleanup.call
