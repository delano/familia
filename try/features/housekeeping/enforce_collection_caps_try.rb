# try/features/housekeeping/enforce_collection_caps_try.rb
#
# frozen_string_literal: true

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

# Push-fed capped collections plus an uncapped one the sweep must skip.
class CapChoreCustomer < Familia::Horreum
  feature :housekeeping

  identifier_field :custid
  field :custid

  sorted_set :events,       max_length: 100
  list       :activity_log, max_length: 50
  set        :tags

  chore :enforce_collection_caps, Familia::Features::Housekeeping::EnforceCollectionCaps
end

# Unshift-fed list: subclass overrides keep_for so the head survives.
class HeadKeepingCaps < Familia::Features::Housekeeping::EnforceCollectionCaps
  def keep_for(name)
    name == :inbox ? :head : :tail
  end
end

class CapChoreMailbox < Familia::Horreum
  feature :housekeeping

  identifier_field :boxid
  field :boxid

  list :inbox, max_length: 50

  chore :enforce_collection_caps, HeadKeepingCaps
end

class CapChoreUncapped < Familia::Horreum
  feature :housekeeping

  identifier_field :id
  field :id

  set :tags

  chore :enforce_collection_caps, Familia::Features::Housekeeping::EnforceCollectionCaps
end

@customer = CapChoreCustomer.new(custid: 'cap-chore-cust')
@customer.save
# Seed overage through raw commands: capped writes would trim as they go.
120.times { |i| @customer.events.dbclient.zadd(@customer.events.dbkey, i, "e#{i}") }
60.times  { |i| @customer.activity_log.dbclient.rpush(@customer.activity_log.dbkey, "a#{i}") }
3.times   { |i| @customer.tags.add("t#{i}") }

@mailbox = CapChoreMailbox.new(boxid: 'cap-chore-box')
@mailbox.save
60.times { |i| @mailbox.inbox.dbclient.rpush(@mailbox.inbox.dbkey, "m#{i}") }

@uncapped = CapChoreUncapped.new(id: 'cap-chore-uncapped')
@uncapped.save

## The class itself registers as the chore handler
CapChoreCustomer.chores[:enforce_collection_caps]
#=> Familia::Features::Housekeeping::EnforceCollectionCaps

## chore rejects a callable that does not respond to call
begin
  CapChoreCustomer.chore(:broken, :not_callable)
rescue ArgumentError => e
  e.message
end
#=> "chore :broken callable must respond to #call"

## chore rejects a callable and a block together
begin
  CapChoreCustomer.chore(:ambiguous, proc { true }) { true }
rescue ArgumentError => e
  e.message
end
#=> "chore :ambiguous takes a callable or a block, not both"

## First run trims the overage and returns the removed count (20 + 10)
@customer.do_chore!(:enforce_collection_caps)
#=> 30

## Sorted set is at its cap, keeping the highest scores
[@customer.events.size, @customer.events.first]
#=> [100, 'e20']

## Push-fed list is at its cap, keeping the tail
[@customer.activity_log.size, @customer.activity_log.at(0)]
#=> [50, 'a10']

## Uncapped collection is untouched by the sweep
@customer.tags.size
#=> 3

## Second run removes nothing and returns nil (idempotent)
@customer.do_chore!(:enforce_collection_caps)
#=> nil

## keep_for override trims an unshift-fed list from the tail, keeping the head
@mailbox.do_chore!(:enforce_collection_caps)
#=> 10

## Head survived: first and last elements are the oldest 50
[@mailbox.inbox.at(0), @mailbox.inbox.at(-1)]
#=> ['m0', 'm49']

## A model with no capped collections is a clean no-op
@uncapped.do_chore!(:enforce_collection_caps)
#=> nil

## run_chores! aggregates the chore across instances; re-seeded overage counts as modified
125.times { |i| @customer.events.dbclient.zadd(@customer.events.dbkey, i, "e#{i}") }
CapChoreCustomer.run_chores!.slice(:scanned, :chores)
#=> {scanned: 1, chores: {enforce_collection_caps: {modified: 1, errors: 0}}}

## A clean bulk pass reports zero modified
CapChoreCustomer.run_chores!.slice(:scanned, :chores)
#=> {scanned: 1, chores: {enforce_collection_caps: {modified: 0, errors: 0}}}

## Cleanup
@customer.events.delete!
@customer.activity_log.delete!
@customer.tags.delete!
@mailbox.inbox.delete!
@customer.destroy! if @customer.exists?
@mailbox.destroy! if @mailbox.exists?
@uncapped.destroy! if @uncapped.exists?
true
#=> true
