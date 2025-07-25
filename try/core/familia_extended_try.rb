# try/core/familia_extended_try.rb

require 'time'

require_relative '../../lib/familia'
require_relative '../helpers/test_helpers'

## Has all datatype relativess
registered_types = Familia::DataType.registered_types.keys
registered_types.collect(&:to_s).sort
#=> ["counter", "hash", "hashkey", "list", "lock", "set", "sorted_set", "string", "zset"]

## Familia created class methods for datatype list class
Familia::Horreum::ClassMethods.public_method_defined? :list?
#=> true

## Familia created class methods for datatype list class
Familia::Horreum::ClassMethods.public_method_defined? :list
#=> true

## Familia created class methods for datatype list class
Familia::Horreum::ClassMethods.public_method_defined? :lists
#=> true

## A Familia object knows its datatype relatives
Bone.related_fields.is_a?(Hash) && Bone.related_fields.has_key?(:owners)
#=> true

## A Familia object knows its lists
Bone.lists.size
#=> 1

## A Familia object knows if it has a list
Bone.list? :owners
#=> true

## A Familia object can get a specific datatype relatives def
definition = Bone.list :owners
definition.klass
#=> Familia::List

## Familia.now
parsed_time = Familia.now(Time.parse('2011-04-10 20:56:20 UTC').utc)
[parsed_time, parsed_time.is_a?(Numeric), parsed_time.is_a?(Float)]
#=> [1302468980.0, true, true]

## Familia.qnow
Familia.qstamp 10.minutes, time: 1_302_468_980
#=> 1302468600

## Familia::Object.qstamp
Limiter.qstamp(10.minutes, pattern: '%H:%M', time: 1_302_468_980)
#=> '20:50'

## Familia::Object#qstamp
limiter = Limiter.new :request
limiter.qstamp(10.minutes, pattern: '%H:%M', time: 1_302_468_980)
#=> '20:50'
