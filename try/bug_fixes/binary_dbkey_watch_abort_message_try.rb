# try/bug_fixes/binary_dbkey_watch_abort_message_try.rb
#
# frozen_string_literal: true

# A key built from an identifier that is not valid UTF-8 is BINARY. When a
# WATCH aborted, the WatchAbortError message joined the watched keys, and
# joining that key with a non-ASCII UTF-8 key raised
# Encoding::CompatibilityError while building the message. The error was
# not a WatchAbortError, so atomic_write did not retry, the write was lost,
# and rescuing Familia::OptimisticLockError did not catch it. The message
# now shows each key through Familia.loggable_text.

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class ::WatchMsgRec < Familia::Horreum
  prefix 'watchmsg_rec'
  identifier_field :wid
  field :wid
  field :n
end

@cleanup = lambda do
  client = WatchMsgRec.dbclient
  keys = client.scan_each(match: 'watchmsg_rec:*').to_a
  client.del(*keys) unless keys.empty?
end
@cleanup.call

@a = WatchMsgRec.new(wid: "bad\xFF")
@a.save
@b = WatchMsgRec.new(wid: 'élodie')
@b.save
@other = Redis.new(url: Familia.uri.to_s)

## the two watched keys are BINARY and non-ASCII UTF-8
[@a.dbkey.encoding, @b.dbkey.encoding]
#=> [Encoding::BINARY, Encoding::UTF_8]

## a WATCH conflict on the first attempt is retried and the write lands
@calls = 0
result = @a.atomic_write(
  watch_keys: [@a.dbkey, @b.dbkey],
  pre_check: lambda {
    @calls += 1
    @other.hset(@b.dbkey, 'n', '"1"') if @calls == 1
  },
) { @a.n = 2 }
[result, @calls, WatchMsgRec.find_by_id("bad\xFF").n]
#=> [true, 2, 2]

## a conflict on every attempt raises an OptimisticLockError naming both keys
begin
  @a.atomic_write(
    watch_keys: [@a.dbkey, @b.dbkey],
    pre_check: -> { @other.hset(@b.dbkey, 'n', '"1"') },
  ) { @a.n = 3 }
  :no_raise
rescue Familia::OptimisticLockError => e
  [e.message.include?('watchmsg_rec:bad\xFF:object, watchmsg_rec:élodie:object'), e.message.valid_encoding?]
end
#=> [true, true]

@other.close
@cleanup.call
