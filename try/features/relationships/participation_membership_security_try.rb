# try/features/relationships/participation_membership_security_try.rb
#
# frozen_string_literal: true

# Locks in the S4 fix from issue #310: ParticipationMembership#target_instance
# must resolve the database-sourced target_class string through Familia's model
# registry (an implicit allowlist) rather than Object.const_get, so an attacker
# who can write to the database cannot coerce resolution of an arbitrary
# constant.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

PM = Familia::Features::Relationships::ParticipationMembership

# A registered Familia model that target_instance is allowed to resolve.
class SecTargetModel < Familia::Horreum
  identifier_field :id
  field :id
  field :name
end

def build_membership(target_class, target_id = 'x')
  PM.new(
    target_class: target_class,
    target_id: target_id,
    collection_name: :things,
    type: :set,
    score: nil,
    decoded_score: nil,
    position: nil
  )
end

## nil target_class returns nil
build_membership(nil).target_instance
#=> nil

## A real Ruby constant that is NOT a Familia model does not resolve (no const_get)
build_membership('File').target_instance
#=> nil

## Object/Kernel cannot be coerced via the persisted class name
build_membership('Object').target_instance
#=> nil

## An unknown / namespaced class name returns nil instead of raising
build_membership('Definitely::Not::A::Class').target_instance
#=> nil

## A registered Familia model name resolves and loads the saved instance
@obj = SecTargetModel.new(id: 'sec-target-1', name: 'ok')
@obj.save
loaded = build_membership('SecTargetModel', 'sec-target-1').target_instance
[loaded.is_a?(SecTargetModel), loaded&.id]
#=> [true, "sec-target-1"]

## A registered model name with a missing id resolves the class but returns nil
build_membership('SecTargetModel', 'no-such-id').target_instance
#=> nil

# Teardown
@obj.destroy! rescue nil
