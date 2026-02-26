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

## touch_instances! adds object to instances sorted set
@w1 = RegistryTestWidget.new(widget_id: 'reg_w1', label: 'Alpha')
@w1.commit_fields
RegistryTestWidget.instances.member?('reg_w1')
#=> true

## touch_instances! is idempotent -- calling twice does not duplicate
@w1.touch_instances!
@w1.touch_instances!
RegistryTestWidget.instances.members.count { |m| m == 'reg_w1' }
#=> 1

## touch_instances! updates timestamp but maintains single entry
@score_before = RegistryTestWidget.instances.score('reg_w1')
sleep 0.01
@w1.touch_instances!
@score_after = RegistryTestWidget.instances.score('reg_w1')
[@score_after >= @score_before, RegistryTestWidget.instances.members.count { |m| m == 'reg_w1' }]
#=> [true, 1]

## touch_instances! raises NoIdentifier for nil identifier
@empty = RegistryTestWidget.new
begin
  @empty.touch_instances!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## touch_instances! raises NoIdentifier for empty string identifier
@blank = RegistryTestWidget.new(widget_id: '')
begin
  @blank.touch_instances!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## remove_from_instances! removes entry from instances sorted set
@w2 = RegistryTestWidget.new(widget_id: 'reg_w2', label: 'Beta')
@w2.save
@before = RegistryTestWidget.instances.member?('reg_w2')
@w2.remove_from_instances!
@after = RegistryTestWidget.instances.member?('reg_w2')
[@before, @after]
#=> [true, false]

## remove_from_instances! is idempotent -- calling on unregistered object is no-op
@w2.remove_from_instances!
@w2.remove_from_instances!
RegistryTestWidget.instances.member?('reg_w2')
#=> false

## remove_from_instances! raises NoIdentifier for nil identifier
@empty2 = RegistryTestWidget.new
begin
  @empty2.remove_from_instances!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## remove_from_instances! raises NoIdentifier for empty string identifier
@blank2 = RegistryTestWidget.new(widget_id: '')
begin
  @blank2.remove_from_instances!
  false
rescue Familia::NoIdentifier
  true
end
#=> true

## in_instances? returns true after touch_instances!
@w3 = RegistryTestWidget.new(widget_id: 'reg_w3', label: 'Gamma')
@w3.touch_instances!
RegistryTestWidget.in_instances?('reg_w3')
#=> true

## in_instances? returns false after remove_from_instances!
@w3.remove_from_instances!
RegistryTestWidget.in_instances?('reg_w3')
#=> false

## in_instances? returns false for empty string
RegistryTestWidget.in_instances?('')
#=> false

## in_instances? returns false for nil
RegistryTestWidget.in_instances?(nil)
#=> false

## in_instances? returns false for never-saved identifier
RegistryTestWidget.in_instances?('never_existed_xyz')
#=> false

## destroy! calls remove_from_instances! -- object removed from instances
@w4 = RegistryTestWidget.new(widget_id: 'reg_w4', label: 'Delta')
@w4.save
@before_destroy = RegistryTestWidget.in_instances?('reg_w4')
@w4.destroy!
@after_destroy = RegistryTestWidget.in_instances?('reg_w4')
[@before_destroy, @after_destroy]
#=> [true, false]

# Cleanup
RegistryTestWidget.instances.clear
RegistryTestWidget.all.each(&:destroy!)
