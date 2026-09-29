# try/bug_fixes/horreum_refresh_exception_safety_try.rb
#
# frozen_string_literal: true

# Horreum#refresh! resets the transient fields, sets every persistent field
# except the identifier field to nil, and then assigns the stored values
# through the setters (the reset is pinned in
# try/bug_fixes/horreum_refresh_absent_fields_try.rb). A setter can raise on
# a stored value: an application setter that validates its input, or an
# encrypted field whose stored envelope names an algorithm this process does
# not provide.
#
# Because of the reset, stopping at the failing setter would leave every
# field after it nil, and a save after that would remove those fields from
# the stored hash. The #remove_stale_nil_fields docstring in
# lib/familia/horreum/persistence.rb says: "Because it removes every field
# that is nil in memory, save/commit_fields are a full-overwrite of scalar
# state". So refresh! puts the object back as it was before re-raising:
# field values, transient fields and dirty tracking. This file pins that for
# an application setter and for an encrypted field, including that a save
# afterwards keeps every stored field.
#
# Before refresh! reset the persistent fields, a setter that raised stopped
# it with the fields before the failing one assigned and marked dirty and the
# transient fields reset. The fields after it kept their in-memory values,
# and a later save wrote those back.

require_relative '../support/helpers/test_helpers'

# Models for this file.
module RefreshExceptionSafetyTry
  # A record whose handle setter rejects long values.
  class Profile < Familia::Horreum
    prefix :refresh_exsafe_profile
    feature :transient_fields
    identifier_field :pid
    field :pid
    field :handle
    field :bio
    field :plan
    transient_field :session_note

    # Prepended so that super reaches the setter the field defines.
    prepend(Module.new do
      def handle=(value)
        raise ArgumentError, "handle too long: #{value.size}" if value && value.size > 8

        super
      end
    end)
  end

  # A record with encrypted fields.
  class Vault < Familia::Horreum
    prefix :refresh_exsafe_vault
    feature :encrypted_fields
    identifier_field :vid
    field :vid
    field :name
    encrypted_field :api_key
    encrypted_field :token
  end
end

set_test_encryption_keys({ v1: Base64.strict_encode64('a' * 32) }, current_version: :v1)

@raw = Familia.dbclient

@profile = RefreshExceptionSafetyTry::Profile.new(pid: 'exsafe_p1', handle: 'alice', bio: 'hello', plan: 'pro')
@profile.save
@profile.session_note = 'kept in memory'
@profile.plan = 'unsaved'
# Another writer stores a handle the setter rejects.
@raw.hset(@profile.dbkey, 'handle', '"a-very-long-handle"')

## refresh! raises the setter's error
begin
  @profile.refresh!
  :no_error
rescue ArgumentError => e
  e.message
end
#=> 'handle too long: 18'

## after the failed refresh! every field keeps its in-memory value, including the unsaved one
[@profile.handle, @profile.bio, @profile.plan]
#=> ['alice', 'hello', 'unsaved']

## the transient field keeps its value
@profile.session_note.value
#=> 'kept in memory'

## dirty tracking is what it was before the call
@profile.changed_fields
#=> { plan: ['pro', 'unsaved'] }

## a save after the failed refresh! keeps the stored fields the refresh did not assign
@raw.hset(@profile.dbkey, 'handle', '"bob"')
@profile.save
@raw.hgetall(@profile.dbkey).keys.sort
#=> ['bio', 'handle', 'pid', 'plan']

## once the stored value is accepted, refresh! assigns it and clears dirty tracking
@raw.hset(@profile.dbkey, 'handle', '"carol"')
@profile.plan = 'unsaved again'
@profile.refresh!
[@profile.handle, @profile.plan, @profile.session_note, @profile.dirty?]
#=> ['carol', 'unsaved', nil, false]

## refresh! raises for a stored envelope with an unregistered algorithm
@vault = RefreshExceptionSafetyTry::Vault.new(vid: 'exsafe_v1', name: 'n', api_key: 'AK', token: 'TK')
@vault.save
# Another writer stores an api_key envelope whose algorithm is not available here.
@envelope = JSON.parse(@raw.hget(@vault.dbkey, 'api_key'))
@envelope['algorithm'] = 'unregistered-algorithm'
@raw.hset(@vault.dbkey, 'api_key', JSON.dump(@envelope))
begin
  @vault.refresh!
  :no_error
rescue Familia::EncryptionError => e
  e.message
end
#=> 'Unsupported algorithm: unregistered-algorithm'

## the encrypted fields keep their in-memory values
[@vault.name, @vault.api_key.nil?, @vault.token.reveal { |plain| plain }]
#=> ['n', false, 'TK']

## the object is still clean
@vault.dirty?
#=> false

## a save after the failed refresh! keeps every stored field
@vault.save
@raw.hgetall(@vault.dbkey).keys.sort
#=> ['api_key', 'name', 'token', 'vid']

delete_test_dbkeys(RefreshExceptionSafetyTry::Profile, RefreshExceptionSafetyTry::Vault)
clear_test_encryption_keys
