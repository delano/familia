require 'familia'
require 'familia/test_helpers'

## Has all redis objects
redis_objects = Familia::Object::RedisObject.klasses.keys
redis_objects.collect(&:to_s).sort
#=> ["hash", "list", "set", "string", "zset"]

## Familia::Object created class methods for redis object class
Familia::Object::ClassMethods.public_method_defined? :list?
#=> true

## Familia::Object created class methods for redis object class
Familia::Object::ClassMethods.public_method_defined? :list
#=> true

## Familia::Object created class methods for redis object class
Familia::Object::ClassMethods.public_method_defined? :lists
#=> true

## A Familia object knows its redis objects
Bone.redis_objects.is_a?(Hash) && Bone.redis_objects.has_key?(:owners)
#=> true

## A Familia object knows its lists
Bone.lists.size
#=> 1

## A Familia object knows if it has a list
Bone.list? :owners
#=> true

## A Familia object can get a specific redis object def
definition = Bone.list :owners
definition.klass
#=> Familia::Object::List
