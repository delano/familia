require_relative '../support/helpers/test_helpers'

Familia.debug = false

# Test class with expiration feature, multiple relation types,
# and varied per-relation expiration options.
class CascadeTestWidget < Familia::Horreum
  feature :expiration

  identifier_field :widgetid
  field :widgetid
  field :name

  default_expiration 3600 # 1 hour

  # Relation with its own default_expiration (should override parent)
  list :events, default_expiration: 7200   # 2 hours

  # Relation without its own expiration (inherits parent via cascade)
  set :tags

  # Relation with no_expiration (excluded from cascade)
  hashkey :permanent_config, no_expiration: true

  # SortedSet with its own TTL
  sorted_set :metrics, default_expiration: 1800  # 30 minutes

  # StringKey inheriting parent TTL
  string :status_msg
end

# Clean up from prior runs
CascadeTestWidget.instances.clear
CascadeTestWidget.all.each(&:destroy!)

## class default_expiration is set
CascadeTestWidget.default_expiration
#=> 3600.0

## object inherits class default_expiration
@w = CascadeTestWidget.new(widgetid: 'cascade_w1', name: 'Widget A')
@w.default_expiration
#=> 3600.0

## save applies TTL to main hash key
@w.save
@main_ttl = CascadeTestWidget.dbclient.ttl(@w.dbkey)
@main_ttl > 3500 && @main_ttl <= 3600
#=> true

## list with own default_expiration uses its own TTL on write
@w.events.push('created')
@events_ttl = CascadeTestWidget.dbclient.ttl(@w.events.dbkey)
@events_ttl > 7100 && @events_ttl <= 7200
#=> true

## sorted_set with own default_expiration uses its own TTL on write
@w.metrics.add('cpu', 95.5)
@metrics_ttl = CascadeTestWidget.dbclient.ttl(@w.metrics.dbkey)
@metrics_ttl > 1700 && @metrics_ttl <= 1800
#=> true

## hashkey with no_expiration has no TTL set
@w.permanent_config['key1'] = 'value1'
@config_ttl = CascadeTestWidget.dbclient.ttl(@w.permanent_config.dbkey)
@config_ttl
#=> -1

## set without own expiration inherits parent TTL on write
# Relations without default_expiration inherit the parent's TTL via
# the DataType default_expiration cascade. When tags.add calls
# update_expiration, it resolves to the parent's 3600.
@w.tags.add('test')
@tags_ttl = CascadeTestWidget.dbclient.ttl(@w.tags.dbkey)
@tags_ttl > 3500 && @tags_ttl <= 3600
#=> true

## explicit update_expiration on parent re-cascades to relations
@w.update_expiration
@tags_ttl_after = CascadeTestWidget.dbclient.ttl(@w.tags.dbkey)
@tags_ttl_after > 3500 && @tags_ttl_after <= 3600
#=> true

## cascade applies parent TTL to string without own expiration
@w.status_msg.set('active')
@w.update_expiration
@status_ttl = CascadeTestWidget.dbclient.ttl(@w.status_msg.dbkey)
@status_ttl > 3500 && @status_ttl <= 3600
#=> true

## explicit expiration overrides class default for parent key
@w.update_expiration(expiration: 900)
@override_ttl = CascadeTestWidget.dbclient.ttl(@w.dbkey)
@override_ttl > 800 && @override_ttl <= 900
#=> true

## explicit expiration does not override relation-specific TTL
# The events list has default_expiration: 7200, so the cascade
# uses 7200 even when the parent gets an explicit 900.
@events_ttl_after = CascadeTestWidget.dbclient.ttl(@w.events.dbkey)
@events_ttl_after > 7100 && @events_ttl_after <= 7200
#=> true

## explicit expiration cascades to relations without own TTL
# The tags set has no default_expiration, so it gets the
# explicitly passed value (900) via the cascade fallback.
@tags_ttl_explicit = CascadeTestWidget.dbclient.ttl(@w.tags.dbkey)
@tags_ttl_explicit > 800 && @tags_ttl_explicit <= 900
#=> true

## no_expiration relation still has no TTL after explicit cascade
@config_ttl_after = CascadeTestWidget.dbclient.ttl(@w.permanent_config.dbkey)
@config_ttl_after
#=> -1

## full lifecycle: save then populate then cascade applies correctly
@w2 = CascadeTestWidget.new(widgetid: 'cascade_w2', name: 'Widget B')
@w2.save
@w2.events.push('init')
@w2.tags.add('new')
@w2.metrics.add('load', 50.0)
@w2.status_msg.set('pending')
@w2.permanent_config['mode'] = 'debug'
# Trigger cascade to propagate parent TTL to relations without own TTL
@w2.update_expiration
@w2_main = CascadeTestWidget.dbclient.ttl(@w2.dbkey)
@w2_events = CascadeTestWidget.dbclient.ttl(@w2.events.dbkey)
@w2_tags = CascadeTestWidget.dbclient.ttl(@w2.tags.dbkey)
@w2_metrics = CascadeTestWidget.dbclient.ttl(@w2.metrics.dbkey)
@w2_config = CascadeTestWidget.dbclient.ttl(@w2.permanent_config.dbkey)
[@w2_main > 3500, @w2_events > 7100, @w2_tags > 3500, @w2_metrics > 1700, @w2_config == -1]
#=> [true, true, true, true, true]

# Cleanup
CascadeTestWidget.instances.clear
CascadeTestWidget.all.each(&:destroy!)
