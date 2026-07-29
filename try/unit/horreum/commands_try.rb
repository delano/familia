# try/unit/horreum/commands_try.rb
#
# frozen_string_literal: true

# try/horreum/commands_try.rb

# Test Horreum Valkey/Redis commands

require_relative '../../support/helpers/test_helpers'

## hget/hset operations
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
    field :score
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:hset) && user.respond_to?(:hget)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## increment/decrement operations not available
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
    field :score
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:incr) && user.respond_to?(:decr)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## field existence and key operations not available
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:key?)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## bulk field operations availability
begin
  user_class = Class.new(Familia::Horreum) do
    identifier_field :email
    field :email
    field :name
  end

  user = user_class.new(email: "test@example.com", name: "Test")
  user.save

  result = user.respond_to?(:hkeys) && user.respond_to?(:hvals) && user.respond_to?(:hgetall)
  user.delete!
  result
rescue StandardError => e
  user&.delete! rescue nil
  false
end
#=> false

## incr initializes a missing hash field to 1
@counter_bone = Bone.new(token: "commands_try_#{Time.now.to_i}_#{Process.pid}", name: 'counters')
@counter_bone.save
@counter_bone.incr('points')
#=> 1

## increment alias increments by 1
@counter_bone.increment('points')
#=> 2

## incrby increments by the given amount
@counter_bone.incrby('points', 10)
#=> 12

## incrementby alias increments by the given amount
@counter_bone.incrementby('points', 3)
#=> 15

## decr decrements by 1
@counter_bone.decr('points')
#=> 14

## decrement alias decrements by 1
@counter_bone.decrement('points')
#=> 13

## decrby decrements by the given amount
@counter_bone.decrby('points', 4)
#=> 9

## decrementby alias decrements by the given amount
@counter_bone.decrementby('points', 9)
#=> 0

## decrby accepts a numeric string decrement
@counter_bone.decrby('points', '5')
#=> -5

## decrby raises on a non-integer decrement
begin
  @counter_bone.decrby('points', 'not-a-number')
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## incrby accepts a numeric string increment
@counter_bone.incrby('points', '5')
#=> 0

## incrby raises on a fractional increment instead of truncating it
begin
  @counter_bone.incrby('points', 2.5)
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## decrby raises on a fractional decrement instead of truncating it
begin
  @counter_bone.decrby('points', 2.5)
rescue ArgumentError => e
  e.class
end
#=> ArgumentError

## incr then decr returns the field to its original value
before = @counter_bone.hget('points').to_i
@counter_bone.incr('points')
@counter_bone.decr('points')
@counter_bone.hget('points').to_i == before
#=> true

## decr on a missing field initializes it to -1
@counter_bone.decr('fresh_field')
#=> -1

## decrby on a missing field initializes it to the negated amount
@counter_bone.decrby('fresh_field2', 7)
#=> -7

## cleanup: delete the counter object key
@counter_bone.delete!
#=> 1
