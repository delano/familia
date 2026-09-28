# try/bug_fixes/hashkey_refresh_read_only_try.rb
#
# frozen_string_literal: true

# HashKey#refresh! read the hash with HGETALL and then passed the result to
# #update, which sent HMSET with the values it had just read, reset the key's
# expiration, and ran the dirty-write check against the parent. A HashKey
# keeps no field values in memory, so the write-back reloaded nothing. The
# Valkey HMSET documentation (https://valkey.io/commands/hmset/) says: "This
# command overwrites any specified fields already existing in the hash." A
# value another client wrote between the read and the HMSET was therefore
# replaced by the value read before it.
#
# refresh! now only reads. It returns the fields it read and still raises
# Familia::KeyNotFoundError for a missing hash (see
# try/bug_fixes/refresh_missing_key_try.rb). refresh returns self.

require_relative '../support/helpers/test_helpers'

# Models and helpers for this file.
module RefreshReadOnlyTry
  # A record with one hash collection.
  class Record < Familia::Horreum
    prefix :refresh_ro_record
    identifier_field :rid
    field :rid
    field :name
    hashkey :props
  end

  # The same shape, with dirty-write warnings escalated to errors.
  class StrictRecord < Familia::Horreum
    prefix :refresh_ro_strict
    dirty_write_warnings :strict
    identifier_field :rid
    field :rid
    field :name
    hashkey :props
  end

  # Stands in for another client that writes to the hash immediately after
  # refresh! has read it.
  class InterleavedHashKey < Familia::HashKey
    def hgetall
      fields = super
      Familia.dbclient.hset(dbkey, 'color', Familia::JsonSerializer.dump('red'))
      fields
    end
  end
end

@raw = Familia.dbclient
@rec = RefreshReadOnlyTry::Record.new(rid: 'refresh_ro_rec', name: 'stored')
@rec.save
@rec.props['color'] = 'blue'
@rec.props['size'] = 3

## refresh! returns the fields it read, deserialized
@rec.props.refresh!
#=> {'color' => 'blue', 'size' => 3}

## refresh returns the HashKey itself
@rec.props.refresh.equal?(@rec.props)
#=> true

## a write landing after refresh! has read the hash is not overwritten
@interleaved = RefreshReadOnlyTry::InterleavedHashKey.new('refresh_ro:interleaved')
@raw.hset(@interleaved.dbkey, 'color', Familia::JsonSerializer.dump('blue'))
@read = @interleaved.refresh!
[@read['color'], @interleaved['color']]
#=> ['blue', 'red']

## refresh! leaves the key's expiration as it was
@expiring = Familia::HashKey.new('refresh_ro:expiring', default_expiration: 3600)
@expiring['color'] = 'blue'
@raw.expire(@expiring.dbkey, 100)
@expiring.refresh!
@raw.ttl(@expiring.dbkey).between?(1, 100)
#=> true

## refresh leaves the key's expiration as it was
@expiring.refresh
@raw.ttl(@expiring.dbkey).between?(1, 100)
#=> true

## refresh! leaves a value another client stored unencoded as it was
@raw.hset(@rec.props.dbkey, 'plain', 'not-json')
@rec.props.refresh!
@raw.hget(@rec.props.dbkey, 'plain')
#=> 'not-json'

## refresh! does not run the dirty-write check when the parent has unsaved field changes
@strict = RefreshReadOnlyTry::StrictRecord.new(rid: 'refresh_ro_strict', name: 'stored')
@strict.save
@strict.props['color'] = 'blue'
@strict.name = 'unsaved'
@strict.props.refresh!
#=> {'color' => 'blue'}

## a write through the same HashKey still runs the dirty-write check
@strict.props['size'] = 3
#=!> Familia::Problem

delete_test_dbkeys(RefreshReadOnlyTry::Record, RefreshReadOnlyTry::StrictRecord, 'refresh_ro:*')
