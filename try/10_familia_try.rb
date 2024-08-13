
require 'time'

require_relative '../lib/familia'
require_relative './test_helpers'

## Has all redistype relativess
redistype_relatives = Familia::RedisType.registered_types.keys
redistype_relatives.collect(&:to_s).sort
#=> ["counter", "hash", "hashkey", "list", "lock", "set", "sorted_set", "string", "zset"]

## Familia created class methods for redistype list class
Familia::Horreum::ClassMethods.public_method_defined? :list?
#=> true

## Familia created class methods for redistype list class
Familia::Horreum::ClassMethods.public_method_defined? :list
#=> true

## Familia created class methods for redistype list class
Familia::Horreum::ClassMethods.public_method_defined? :lists
#=> true

## A Familia object knows its redistype relativess
Bone.redistype_relatives.is_a?(Hash) && Bone.redistype_relatives.has_key?(:owners)
#=> true

## A Familia object knows its lists
Bone.lists.size
#=> 1

## A Familia object knows if it has a list
Bone.list? :owners
#=> true

## A Familia object can get a specific redistype relatives def
definition = Bone.list :owners
definition.klass
#=> Familia::List

## Familia.now
Familia.now Time.parse('2011-04-10 20:56:20 UTC').utc
#=> 1302468980

## Familia.qnow
Familia.qnow 10.minutes, 1302468980
#=> 1302468600

## Familia::Object.qstamp
Limiter.qstamp 10.minutes, '%H:%M', 1302468980
#=> '20:50'

## Familia::Object#qstamp
limiter = Limiter.new :request
limiter.qstamp 10.minutes, '%H:%M', 1302468980
##=> '20:50'
