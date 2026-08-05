# try/features/expiration/long_ttl_try.rb
#
# frozen_string_literal: true

# Regression test for TTL values above 30 days (#4008).
#
# Verifies that Familia correctly sets, reads, cascades, and extends
# expiration values larger than 2_592_000 seconds (30 days) on both
# Horreum objects and their related DataType fields.

require_relative '../../support/helpers/test_helpers'

Familia.debug = false

SECONDS_PER_DAY = 86_400

# ------------------------------------------------------------------
# Test class: Horreum with > 30-day TTL and multiple relation types
# ------------------------------------------------------------------
class LongTTLWidget < Familia::Horreum
  feature :expiration

  identifier_field :widget_id
  field :widget_id
  field :name

  default_expiration 45 * SECONDS_PER_DAY

  list       :events,           default_expiration: 60 * SECONDS_PER_DAY
  set        :tags
  hashkey    :permanent_config, no_expiration: true
  sorted_set :metrics,          default_expiration: 90 * SECONDS_PER_DAY
  string     :status_msg
end

LongTTLWidget.instances.clear
LongTTLWidget.all.each(&:destroy!)

# ------------------------------------------------------------------
# Class-level configuration
# ------------------------------------------------------------------

## class default_expiration is 45 days in seconds
LongTTLWidget.default_expiration
#=> 3888000.0

# ------------------------------------------------------------------
# TTL on save: main hash key
# ------------------------------------------------------------------

## main hash TTL is greater than 30 days (2_592_000s)
@w = LongTTLWidget.new(widget_id: 'long_ttl_w1', name: 'Widget A')
@w.save
@main_ttl = LongTTLWidget.dbclient.ttl(@w.dbkey)
@main_ttl > 2_592_000
#=> true

## main hash TTL is within 5s of 45 days (3_888_000s)
(@main_ttl - 3_888_000).abs <= 5
#=> true

# ------------------------------------------------------------------
# Cascade to relations with explicit > 30-day TTL
# ------------------------------------------------------------------

## list with 60-day TTL gets correct value on write
@w.events.push('created')
@events_ttl = LongTTLWidget.dbclient.ttl(@w.events.dbkey)
@events_ttl > 5_000_000 && @events_ttl <= 5_184_000
#=> true

## sorted_set with 90-day TTL gets correct value on write
@w.metrics.add('cpu', 95.5)
@metrics_ttl = LongTTLWidget.dbclient.ttl(@w.metrics.dbkey)
@metrics_ttl > 7_700_000 && @metrics_ttl <= 7_776_000
#=> true

# ------------------------------------------------------------------
# Cascade to relations inheriting parent > 30-day TTL
# ------------------------------------------------------------------

## set without own TTL inherits parent 45-day TTL
@w.tags.add('test')
@tags_ttl = LongTTLWidget.dbclient.ttl(@w.tags.dbkey)
@tags_ttl > 3_800_000 && @tags_ttl <= 3_888_000
#=> true

## string without own TTL inherits parent 45-day TTL via cascade
@w.status_msg.set('active')
@w.update_expiration
@status_ttl = LongTTLWidget.dbclient.ttl(@w.status_msg.dbkey)
@status_ttl > 3_800_000 && @status_ttl <= 3_888_000
#=> true

## no_expiration relation is excluded from cascade
@w.permanent_config['key1'] = 'value1'
LongTTLWidget.dbclient.ttl(@w.permanent_config.dbkey)
#=> -1

# ------------------------------------------------------------------
# Explicit update_expiration with values > 30 days
# ------------------------------------------------------------------

## explicit 31-day TTL sets correctly
@w.update_expiration(expiration: 31 * SECONDS_PER_DAY)
@ttl_31d = LongTTLWidget.dbclient.ttl(@w.dbkey)
(@ttl_31d - 2_678_400).abs <= 2
#=> true

## explicit 60-day TTL sets correctly
@w.update_expiration(expiration: 60 * SECONDS_PER_DAY)
@ttl_60d = LongTTLWidget.dbclient.ttl(@w.dbkey)
(@ttl_60d - 5_184_000).abs <= 2
#=> true

## explicit 90-day TTL sets correctly
@w.update_expiration(expiration: 90 * SECONDS_PER_DAY)
@ttl_90d = LongTTLWidget.dbclient.ttl(@w.dbkey)
(@ttl_90d - 7_776_000).abs <= 2
#=> true

## explicit 180-day TTL sets correctly
@w.update_expiration(expiration: 180 * SECONDS_PER_DAY)
@ttl_180d = LongTTLWidget.dbclient.ttl(@w.dbkey)
(@ttl_180d - 15_552_000).abs <= 2
#=> true

## explicit 365-day TTL sets correctly
@w.update_expiration(expiration: 365 * SECONDS_PER_DAY)
@ttl_365d = LongTTLWidget.dbclient.ttl(@w.dbkey)
(@ttl_365d - 31_536_000).abs <= 2
#=> true

# ------------------------------------------------------------------
# extend_expiration crossing the 30-day boundary
# ------------------------------------------------------------------

## extend_expiration from 15 days by 20 days results in > 30 days
@w2 = LongTTLWidget.new(widget_id: 'long_ttl_w2', name: 'Widget B')
@w2.save
@w2.update_expiration(expiration: 15 * SECONDS_PER_DAY)
@w2.extend_expiration(20 * SECONDS_PER_DAY)
@extended_ttl = @w2.ttl
@extended_ttl > 2_592_000
#=> true

## extended TTL is within 5s of 35 days (3_024_000s)
(@extended_ttl - 3_024_000).abs <= 5
#=> true

# ------------------------------------------------------------------
# ttl_report with > 30-day values
# ------------------------------------------------------------------

## ttl_report main key shows > 30 days
@w.update_expiration(expiration: 45 * SECONDS_PER_DAY)
@report = @w.ttl_report
@report[:main][:ttl] > 2_592_000
#=> true

## ttl_report relations show correct TTL values
@report[:relations][:events][:ttl] > 5_000_000
#=> true

## ttl_report no_expiration relation shows -1
@report[:relations][:permanent_config][:ttl]
#=> -1

# ------------------------------------------------------------------
# Instance-level override with > 30-day TTL
# ------------------------------------------------------------------

## instance-level default_expiration override with > 30 days
@w3 = LongTTLWidget.new(widget_id: 'long_ttl_w3', name: 'Widget C')
@w3.default_expiration = 60 * SECONDS_PER_DAY
@w3.default_expiration
#=> 5184000.0

## save with instance override applies correct TTL
@w3.save
@w3_ttl = @w3.ttl
(@w3_ttl - 5_184_000).abs <= 5
#=> true

# ------------------------------------------------------------------
# persist! on > 30-day object removes TTL
# ------------------------------------------------------------------

## persist! removes TTL from object with > 30-day expiration
@w3.persist!
@w3.ttl
#=> -1

# Cleanup
LongTTLWidget.instances.clear
LongTTLWidget.all.each(&:destroy!)
