require 'familia'
require 'familia/test_helpers'

@a = Bone.new 'atoken', 'akey'

## Familia::Object::HashKey#has_key? knows when there's no key
@a.props.has_key? 'fieldA'
#=> false

## Familia::Object::HashKey#[]=
@a.props['fieldA'] = '1'
@a.props['fieldB'] = '2'
@a.props['fieldC'] = '3'
#=> '3'

## Familia::Object::HashKey#[]
@a.props['fieldA']
#=> '1'

## Familia::Object::HashKey#has_key? knows when there's a key
@a.props.has_key? 'fieldA'
#=> true

## Familia::Object::HashKey#all 
@a.props.all.class
#=> Hash

## Familia::Object::HashKey#size counts the number of keys
@a.props.size
#=> 3

## Familia::Object::HashKey#remove
@a.props.remove 'fieldB'
#=> 1

## Familia::Object::HashKey#values
@a.props.values.sort
#=> ['1', '3']

## Familia::Object::HashKey#increment
@a.props.increment 'counter', 100
#=> 100

## Familia::Object::HashKey#decrement
@a.props.decrement 'counter', 60
#=> 40

## Familia::Object::HashKey#values_at
@a.props.values_at 'fieldA', 'counter', 'fieldC'
#=> ['1', '40', '3']


@a.props.destroy!
