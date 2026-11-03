# try/unit/core/escape_glob_try.rb
#
# frozen_string_literal: true

# Familia.escape_glob escapes the characters that KEYS and SCAN MATCH read
# as glob syntax, so text built from data matches only itself inside a key
# pattern. The first testcases pin the string transformation. The rest
# send escaped patterns to the server next to rival keys that the
# unescaped pattern would also match.

require_relative '../../support/helpers/test_helpers'

@ns = 'escape_glob_try'
@dbclient = Familia.dbclient

# Literal identifiers holding each glob special character, plus the caret
# and hyphen inside brackets, a trailing backslash and a wildcard after an
# invalid UTF-8 byte.
@literals = ['c-*', 'c?1', 'c[12]', 'c]1', 'c\\1', 'c\\', 'c[^x]', 'c[a-z]', 'c\\*', "bad\xFF-*"]

# Keys that an unescaped pattern built from one of the literals would
# also match, e.g. "c-*" matches "c-1", "c[12]" matches "c1", "c\\1"
# matches "c1" and "c[^x]" matches "cy".
@rivals = ['c-1', 'c-2', 'cx1', 'c1', 'c2', 'cy', 'cb', 'c*', "bad\xFF-1"]

@key_for = ->(id) { "#{@ns}:#{id}:k" }
@all_keys = (@literals + @rivals).map(&@key_for)
@dbclient.del(*@all_keys)
@all_keys.each { |key| @dbclient.set(key, '1') }

# The client returns a key that is not valid UTF-8 as a binary String, so
# the testcases below compare keys as bytes.
@scan_all = lambda do |pattern|
  found = []
  cursor = '0'
  loop do
    cursor, batch = @dbclient.scan(cursor, match: pattern, count: 1000)
    found.concat(batch)
    break if cursor == '0'
  end
  found.sort
end

## each glob special character is escaped with a backslash
['*', '?', '[', ']', '\\'].map { |char| Familia.escape_glob(char) }
#=> ["\\*", "\\?", "\\[", "\\]", "\\\\"]

## several special characters in one string are escaped in place
Familia.escape_glob('a*b?c[d]e\\f')
#=> "a\\*b\\?c\\[d\\]e\\\\f"

## text without special characters is returned unchanged
Familia.escape_glob('user:c-1^{x}.@example.com')
#=> "user:c-1^{x}.@example.com"

## caret and hyphen are left alone because the opening bracket is escaped
Familia.escape_glob('c[^a-z]')
#=> "c\\[^a-z\\]"

## non-String input is converted with to_s
[Familia.escape_glob(:'role*'), Familia.escape_glob(42), Familia.escape_glob(nil)]
#=> ["role\\*", "42", ""]

## a frozen input is not modified
input = 'c-*'.dup.freeze
escaped = Familia.escape_glob(input)
[input, escaped]
#=> ["c-*", "c-\\*"]

## a String with invalid UTF-8 bytes is escaped byte for byte and keeps its encoding
escaped = Familia.escape_glob("bad\xFF-*[1]")
[escaped.bytes == "bad\xFF-\\*\\[1\\]".b.bytes, escaped.encoding, escaped.valid_encoding?]
#=> [true, Encoding::UTF_8, false]

## binary data with high bytes is escaped and stays binary
escaped = Familia.escape_glob("bin\xFF?\\".b)
[escaped == "bin\xFF\\?\\\\".b, escaped.encoding]
#=> [true, Encoding::BINARY]

## multibyte UTF-8 text is escaped and stays valid UTF-8
escaped = Familia.escape_glob('café-*[ü]')
[escaped, escaped.encoding, escaped.valid_encoding?]
#=> ["café-\\*\\[ü\\]", Encoding::UTF_8, true]

## the test data has rivals: the unescaped "c-*" pattern also matches c-1 and c-2
@dbclient.keys("#{@ns}:c-*:k").sort
#=> ["escape_glob_try:c-*:k", "escape_glob_try:c-1:k", "escape_glob_try:c-2:k"]

## KEYS with an escaped literal matches only that literal's key, for every literal
@literals.to_h { |id| [id, @dbclient.keys("#{@ns}:#{Familia.escape_glob(id)}:k")] }
  .all? { |id, found| found.map(&:b) == [@key_for.call(id).b] }
#=> true

## SCAN MATCH with an escaped literal matches only that literal's key, for every literal
@literals.to_h { |id| [id, @scan_all.call("#{@ns}:#{Familia.escape_glob(id)}:k")] }
  .all? { |id, found| found.map(&:b) == [@key_for.call(id).b] }
#=> true

## an escaped prefix followed by a real wildcard keeps the wildcard
@scan_all.call("#{Familia.escape_glob("#{@ns}:c[12]")}*")
#=> ["escape_glob_try:c[12]:k"]

## the unescaped rival literal "c*" is itself matched only by its escaped form
@scan_all.call("#{@ns}:#{Familia.escape_glob('c*')}:k")
#=> ["escape_glob_try:c*:k"]

@dbclient.del(*@all_keys)
