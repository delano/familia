require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Dedicated test class with collection types
class SaveCollTestItem < Familia::Horreum
  identifier_field :itemid
  field :itemid
  field :name
  field :status
  list :history
  set :tags
  sorted_set :scores
end

# Clean slate
SaveCollTestItem.instances.clear
SaveCollTestItem.all.each(&:destroy!)

## save_with_collections saves the object and returns true
@item = SaveCollTestItem.new(itemid: 'swc_item1', name: 'Widget')
@item.save_with_collections
#=> true

## saved object is findable after save_with_collections
SaveCollTestItem.find_by_id('swc_item1').nil?
#=> false

## save_with_collections executes the block after save
@item2 = SaveCollTestItem.new(itemid: 'swc_item2', name: 'Gadget')
@item2.save_with_collections do
  @item2.tags.add('electronics')
  @item2.tags.add('sale')
  @item2.history.push('created')
end
@item2.tags.members.sort
#=> ['electronics', 'sale']

## collection data persists after save_with_collections block
@item2.history.members
#=> ['created']

## save_with_collections returns boolean true on success
@item3 = SaveCollTestItem.new(itemid: 'swc_item3', name: 'Doohickey')
result = @item3.save_with_collections { @item3.tags.add('test') }
result == true
#=> true

## block can add to sorted sets during save_with_collections
@item4 = SaveCollTestItem.new(itemid: 'swc_item4', name: 'Thingamajig')
@item4.save_with_collections do
  @item4.scores.add('metric_a', 42.5)
  @item4.scores.add('metric_b', 99.0)
end
@item4.scores.members.sort
#=> ['metric_a', 'metric_b']

## save_with_collections without block just saves
@item5 = SaveCollTestItem.new(itemid: 'swc_item5', name: 'Plain')
@item5.save_with_collections
SaveCollTestItem.find_by_id('swc_item5').name
#=> 'Plain'

## update_expiration parameter is forwarded to save
@item6 = SaveCollTestItem.new(itemid: 'swc_item6', name: 'NoExpiry')
@item6.save_with_collections(update_expiration: false)
#=> true

## object is in instances after save_with_collections
SaveCollTestItem.in_instances?('swc_item1')
#=> true

# Cleanup
SaveCollTestItem.instances.clear
SaveCollTestItem.all.each(&:destroy!)
