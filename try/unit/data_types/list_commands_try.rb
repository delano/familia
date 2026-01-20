# try/unit/data_types/list_commands_try.rb
#
# frozen_string_literal: true

# Tests for additional Redis LIST commands added to Familia::ListKey

require_relative '../../support/helpers/test_helpers'

@a = Bone.new 'listcmds'

## Familia::ListKey#pop with count parameter returns array
@a.owners.push :v1, :v2, :v3, :v4, :v5
result = @a.owners.pop(2)
result
#=> ['v5', 'v4']

## Familia::ListKey#pop with count=1 returns array with single element
result = @a.owners.pop(1)
result
#=> ['v3']

## Familia::ListKey#pop without count returns single element (backward compatible)
result = @a.owners.pop
result
#=> 'v2'

## Familia::ListKey#shift with count parameter returns array
@a.owners.delete!
@a.owners.push :a1, :a2, :a3, :a4, :a5
result = @a.owners.shift(2)
result
#=> ['a1', 'a2']

## Familia::ListKey#shift with count=1 returns array with single element
result = @a.owners.shift(1)
result
#=> ['a3']

## Familia::ListKey#shift without count returns single element (backward compatible)
result = @a.owners.shift
result
#=> 'a4'

## Familia::ListKey#trim reduces list to specified range
@a.owners.delete!
@a.owners.push :t1, :t2, :t3, :t4, :t5
@a.owners.trim(1, 3)
@a.owners.to_a
#=> ['t2', 't3', 't4']

## Familia::ListKey#set updates element at index
@a.owners.set(1, :updated)
@a.owners.to_a
#=> ['t2', 'updated', 't4']

## Familia::ListKey#set with negative index
@a.owners.set(-1, :last_updated)
@a.owners.to_a
#=> ['t2', 'updated', 'last_updated']

## Familia::ListKey#insert before pivot
@a.owners.delete!
@a.owners.push :i1, :i2, :i3
result = @a.owners.insert(:before, :i2, :inserted)
[result, @a.owners.to_a]
#=> [4, ['i1', 'inserted', 'i2', 'i3']]

## Familia::ListKey#insert after pivot
result = @a.owners.insert(:after, :i2, :after_i2)
[result, @a.owners.to_a]
#=> [5, ['i1', 'inserted', 'i2', 'after_i2', 'i3']]

## Familia::ListKey#insert returns -1 when pivot not found
result = @a.owners.insert(:before, :nonexistent, :wont_insert)
result
#=> -1

## Familia::ListKey#insert raises ArgumentError for invalid position
begin
  @a.owners.insert(:invalid, :i2, :value)
  false
rescue ArgumentError => e
  e.message.include?(':before or :after')
end
#=> true

## Familia::ListKey#pushx on existing list returns new length
@a.owners.delete!
@a.owners.push :existing
result = @a.owners.pushx(:px1, :px2)
[result, @a.owners.to_a]
#=> [3, ['existing', 'px1', 'px2']]

## Familia::ListKey#pushx on non-existent list returns 0
@a.owners.delete!
result = @a.owners.pushx(:wont_push)
[result, @a.owners.to_a]
#=> [0, []]

## Familia::ListKey#unshiftx on existing list returns new length
@a.owners.push :existing
result = @a.owners.unshiftx(:ux1, :ux2)
[result, @a.owners.to_a]
#=> [3, ['ux2', 'ux1', 'existing']]

## Familia::ListKey#unshiftx on non-existent list returns 0
@a.owners.delete!
result = @a.owners.unshiftx(:wont_unshift)
[result, @a.owners.to_a]
#=> [0, []]

## Familia::ListKey#move transfers element to another list
@a.owners.delete!
@a.owners.push :m1, :m2, :m3
@dest = Bone.new 'listcmds_dest'
@dest.owners.delete!
result = @a.owners.move(@dest.owners, :right, :left)
[result, @a.owners.to_a, @dest.owners.to_a]
#=> ['m3', ['m1', 'm2'], ['m3']]

## Familia::ListKey#move from left to right
result = @a.owners.move(@dest.owners, :left, :right)
[result, @a.owners.to_a, @dest.owners.to_a]
#=> ['m1', ['m2'], ['m3', 'm1']]

## Familia::ListKey#move returns nil on empty source list
@a.owners.delete!
result = @a.owners.move(@dest.owners, :left, :right)
result
#=> nil

## Familia::ListKey#lset alias works
@a.owners.delete!
@a.owners.push :ls1, :ls2, :ls3
@a.owners.lset(1, :lset_updated)
@a.owners.to_a
#=> ['ls1', 'lset_updated', 'ls3']

## Familia::ListKey#ltrim alias works
@a.owners.delete!
@a.owners.push :a1, :a2, :a3
@a.owners.ltrim(0, 1)
@a.owners.to_a
#=> ['a1', 'a2']

## Familia::ListKey#linsert alias works
@a.owners.delete!
@a.owners.push :li1, :li2, :li3
result = @a.owners.linsert(:after, :li1, :inserted_via_alias)
[result, @a.owners.to_a]
#=> [4, ['li1', 'inserted_via_alias', 'li2', 'li3']]

## Familia::ListKey#rpushx alias works on existing list
@a.owners.delete!
@a.owners.push :existing
result = @a.owners.rpushx(:rpx1)
[result, @a.owners.to_a]
#=> [2, ['existing', 'rpx1']]

## Familia::ListKey#lpushx alias works on existing list
@a.owners.delete!
@a.owners.push :existing
result = @a.owners.lpushx(:lpx1)
[result, @a.owners.to_a]
#=> [2, ['lpx1', 'existing']]

## Familia::ListKey#move with raw string key as destination
@a.owners.delete!
@a.owners.push :raw1, :raw2
raw_dest_key = 'familia:test:raw_dest_list'
Familia.dbclient.del(raw_dest_key)
result = @a.owners.move(raw_dest_key, :right, :left)
dest_contents = Familia.dbclient.lrange(raw_dest_key, 0, -1)
[result, @a.owners.to_a, dest_contents]
#=> ['raw2', ['raw1'], ['"raw2"']]

## Familia::ListKey#lmove alias works
@a.owners.delete!
@a.owners.push :lm1, :lm2
@dest.owners.delete!
result = @a.owners.lmove(@dest.owners, :left, :right)
[result, @a.owners.to_a, @dest.owners.to_a]
#=> ['lm1', ['lm2'], ['lm1']]

@a.owners.delete!
@dest.owners.delete!
Familia.dbclient.del('familia:test:raw_dest_list')
