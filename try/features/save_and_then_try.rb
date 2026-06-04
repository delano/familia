# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class SaveAndThenTestModel < Familia::Horreum
  identifier_field :uid
  field :uid
  field :name
  field :status
  list :history
end

# Clean slate
SaveAndThenTestModel.instances.clear
SaveAndThenTestModel.all.each(&:destroy!)

## save_and_then yields self on successful save
@obj = SaveAndThenTestModel.new(uid: 'sat_1', name: 'Alice')
@yielded = nil
@obj.save_and_then { |o| @yielded = o }
@yielded.equal?(@obj)
#=> true

## save_and_then returns the block's return value on success
@obj2 = SaveAndThenTestModel.new(uid: 'sat_2', name: 'Bob')
@obj2.save_and_then { |o| o.identifier }
#=> 'sat_2'

## save_and_then without a block returns true (like save)
@obj3 = SaveAndThenTestModel.new(uid: 'sat_3', name: 'Carol')
@obj3.save_and_then
#=> true

## save_and_then persists the object before yielding
@obj4 = SaveAndThenTestModel.new(uid: 'sat_4', name: 'Dave')
@exists_in_block = false
@obj4.save_and_then { |o| @exists_in_block = o.exists? }
@exists_in_block
#=> true

## save_and_then allows post-save collection operations
@obj5 = SaveAndThenTestModel.new(uid: 'sat_5', name: 'Eve')
@obj5.save_and_then do |o|
  o.history.push('created')
  o.history.push('welcomed')
end
@obj5.history.members
#=> ['created', 'welcomed']

## save_and_then passes update_expiration through to save
@obj6 = SaveAndThenTestModel.new(uid: 'sat_6', name: 'Frank')
@obj6.save_and_then(update_expiration: false) { |o| o.name }
#=> 'Frank'

# Clean up
SaveAndThenTestModel.instances.clear
SaveAndThenTestModel.all.each(&:destroy!)
