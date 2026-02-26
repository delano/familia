# try/features/ttl_report_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class TTLReportModel < Familia::Horreum
  feature :expiration
  identifier_field :tid
  field :tid
  field :name
  default_expiration 3600 # 1 hour

  list :activity_log
  set :tags
  hashkey :settings
  list :no_expire_data, no_expiration: true
  list :custom_ttl_data, default_expiration: 600 # 10 minutes
end

class NoExpirationModel < Familia::Horreum
  identifier_field :nid
  field :nid
  field :name
end

# Clean up
begin
  existing = Familia.dbclient.keys('ttlreportmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
  existing = Familia.dbclient.keys('noexpirationmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore
end
TTLReportModel.instances.clear
NoExpirationModel.instances.clear

## ttl_report returns a hash with :main and :relations keys
@obj = TTLReportModel.new(tid: 'ttl-report-1', name: 'TTL Test')
@obj.save

# Populate relations so their keys exist in Redis
@obj.activity_log << 'login'
@obj.tags.add 'premium'
@obj.settings['theme'] = 'dark'
@obj.custom_ttl_data << 'recent'
@obj.no_expire_data << 'permanent'

# Re-apply expiration cascade now that relation keys exist
@obj.update_expiration

@report = @obj.ttl_report
@report.keys.sort
#=> [:main, :relations]

## main key entry has :key and :ttl fields
@report[:main].keys.sort
#=> [:key, :ttl]

## main key matches the object dbkey
@report[:main][:key]
#=> @obj.dbkey

## main key has positive TTL after save with default_expiration
@report[:main][:ttl] > 0
#=> true

## main TTL is close to default (within 5 seconds of 3600)
(@report[:main][:ttl] - 3600).abs < 5
#=> true

## relations hash contains all relation keys
@report[:relations].keys.sort
#=> [:activity_log, :custom_ttl_data, :no_expire_data, :settings, :tags]

## cascaded relations show positive TTL
@report[:relations][:tags][:ttl] > 0
#=> true

## cascaded relation TTL is close to default (within 5 seconds of 3600)
(@report[:relations][:tags][:ttl] - 3600).abs < 5
#=> true

## cascaded activity_log also has positive TTL
@report[:relations][:activity_log][:ttl] > 0
#=> true

## no_expiration relation has TTL of -1 (no TTL set)
@report[:relations][:no_expire_data][:ttl]
#=> -1

## custom_ttl relation has its own TTL (close to 600)
(@report[:relations][:custom_ttl_data][:ttl] - 600).abs < 5
#=> true

## relation entries include the correct dbkey
@report[:relations][:tags][:key]
#=> @obj.tags.dbkey

## Detect TTL drift: extend main key but not relations
@obj.extend_expiration(1800) # extend main by 30 minutes
@report2 = @obj.ttl_report
@report2[:main][:ttl] > @report2[:relations][:tags][:ttl]
#=> true

## Model without expiration feature does not have ttl_report
@no_exp = NoExpirationModel.new(nid: 'no-exp-1', name: 'No Exp')
@no_exp.respond_to?(:ttl_report)
#=> false

## Teardown
begin
  existing = Familia.dbclient.keys('ttlreportmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
  existing = Familia.dbclient.keys('noexpirationmodel:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore
end
TTLReportModel.instances.clear
NoExpirationModel.instances.clear
