# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

Familia.debug = false

class CreateBlockTestModel < Familia::Horreum
  identifier_field :uid
  field :uid
  field :name
  list :events
end

# Clean slate: destroy objects first, then clear ghost entries.
CreateBlockTestModel.all.each(&:destroy!)
CreateBlockTestModel.instances.clear

## create! yields the persisted instance to the block
@yielded = nil
@obj = CreateBlockTestModel.create!(uid: 'cb_1', name: 'Alice') { |o| @yielded = o }
@yielded.equal?(@obj)
#=> true

## create! block runs after persistence (object exists in DB)
@exists_in_block = false
CreateBlockTestModel.create!(uid: 'cb_2', name: 'Bob') do |o|
  @exists_in_block = o.exists?
end
@exists_in_block
#=> true

## create! block can perform collection operations
CreateBlockTestModel.create!(uid: 'cb_3', name: 'Carol') do |o|
  o.events.push('account_created')
  o.events.push('welcome_email_sent')
end
CreateBlockTestModel.find_by_id('cb_3').events.members
#=> ['account_created', 'welcome_email_sent']

## create! block is skipped on RecordExistsError
CreateBlockTestModel.create!(uid: 'cb_4', name: 'Dave')
@block_ran = false
begin
  CreateBlockTestModel.create!(uid: 'cb_4', name: 'Duplicate') { |_| @block_ran = true }
rescue Familia::RecordExistsError
  # expected
end
@block_ran
#=> false

## create! returns the created instance regardless of block return value
result = CreateBlockTestModel.create!(uid: 'cb_5', name: 'Eve') { |_| 42 }
result.is_a?(CreateBlockTestModel)
#=> true

# Clean up: destroy objects first, then clear ghost entries.
CreateBlockTestModel.all.each(&:destroy!)
CreateBlockTestModel.instances.clear
