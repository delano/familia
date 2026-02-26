require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Dedicated test class for registry method tests
class RegistryTestWidget < Familia::Horreum
  identifier_field :widget_id
  field :widget_id
  field :label
end

# Clean slate
RegistryTestWidget.instances.clear
RegistryTestWidget.all.each(&:destroy!)

## ensure_registered! adds object to instances sorted set
@w1 = RegistryTestWidget.new(widget_id: 'reg_w1', label: 'Alpha')
@w1.commit_fields
RegistryTestWidget.instances.member?('reg_w1')
#=> true

## ensure_registered! is idempotent -- calling twice does not duplicate
@w1.ensure_registered!
@w1.ensure_registered!
RegistryTestWidget.instances.members.count { |m| m == 'reg_w1' }
#=> 1

## ensure_registered! updates timestamp but maintains single entry
@score_before = RegistryTestWidget.instances.score('reg_w1')
sleep 0.01
@w1.ensure_registered!
@score_after = RegistryTestWidget.instances.score('reg_w1')
[@score_after >= @score_before, RegistryTestWidget.instances.members.count { |m| m == 'reg_w1' }]
#=> [true, 1]

## ensure_registered! raises NoIdentifier for nil identifier
@empty = RegistryTestWidget.new
begin
  @empty.ensure_registered!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## ensure_registered! raises NoIdentifier for empty string identifier
@blank = RegistryTestWidget.new(widget_id: '')
begin
  @blank.ensure_registered!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## unregister! removes entry from instances sorted set
@w2 = RegistryTestWidget.new(widget_id: 'reg_w2', label: 'Beta')
@w2.save
@before = RegistryTestWidget.instances.member?('reg_w2')
@w2.unregister!
@after = RegistryTestWidget.instances.member?('reg_w2')
[@before, @after]
#=> [true, false]

## unregister! is idempotent -- calling on unregistered object is no-op
@w2.unregister!
@w2.unregister!
RegistryTestWidget.instances.member?('reg_w2')
#=> false

## unregister! raises NoIdentifier for nil identifier
@empty2 = RegistryTestWidget.new
begin
  @empty2.unregister!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## unregister! raises NoIdentifier for empty string identifier
@blank2 = RegistryTestWidget.new(widget_id: '')
begin
  @blank2.unregister!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## registered? returns true after ensure_registered!
@w3 = RegistryTestWidget.new(widget_id: 'reg_w3', label: 'Gamma')
@w3.ensure_registered!
RegistryTestWidget.registered?('reg_w3')
#=> true

## registered? returns false after unregister!
@w3.unregister!
RegistryTestWidget.registered?('reg_w3')
#=> false

## registered? returns false for empty string
RegistryTestWidget.registered?('')
#=> false

## registered? returns false for nil
RegistryTestWidget.registered?(nil)
#=> false

## registered? returns false for never-saved identifier
RegistryTestWidget.registered?('never_existed_xyz')
#=> false

## destroy! calls unregister! -- object removed from instances
@w4 = RegistryTestWidget.new(widget_id: 'reg_w4', label: 'Delta')
@w4.save
@before_destroy = RegistryTestWidget.registered?('reg_w4')
@w4.destroy!
@after_destroy = RegistryTestWidget.registered?('reg_w4')
[@before_destroy, @after_destroy]
#=> [true, false]

# Cleanup
RegistryTestWidget.instances.clear
RegistryTestWidget.all.each(&:destroy!)
