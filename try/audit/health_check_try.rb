# try/audit/health_check_try.rb
#
# frozen_string_literal: true

require_relative '../support/helpers/test_helpers'

class HealthCheckModel < Familia::Horreum
  identifier_field :hid
  field :hid
  field :name
end

# Clean up
begin
  existing = Familia.dbclient.keys('health_check_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
HealthCheckModel.instances.clear

## health_check exists as class method
HealthCheckModel.respond_to?(:health_check)
#=> true

## health_check on clean empty state returns AuditReport
@report = HealthCheckModel.health_check
@report.class.name
#=> "Familia::Horreum::AuditReport"

## Empty state is healthy
@report.healthy?
#=> true

## health_check records model_class name
@report.model_class.end_with?('HealthCheckModel')
#=> true

## health_check records audited_at timestamp
@report.audited_at.is_a?(Float)
#=> true

## health_check records duration
@report.duration >= 0
#=> true

## Create consistent objects
@h1 = HealthCheckModel.new(hid: 'hc-1', name: 'One')
@h1.save
@h2 = HealthCheckModel.new(hid: 'hc-2', name: 'Two')
@h2.save
@report = HealthCheckModel.health_check
@report.healthy?
#=> true

## Consistent state: instances counts match
@report.instances[:count_timeline]
#=> 2

## Consistent state: scan counts match
@report.instances[:count_scan]
#=> 2

## Introduce phantom and verify unhealthy
Familia.dbclient.del(@h1.dbkey)
@report = HealthCheckModel.health_check
@report.healthy?
#=> false

## Phantom appears in report
@report.instances[:phantoms]
#=> ['hc-1']

## health_check accepts batch_size
@report = HealthCheckModel.health_check(batch_size: 1)
@report.instances[:phantoms]
#=> ['hc-1']

## health_check accepts progress callback
@progress = []
HealthCheckModel.health_check { |p| @progress << p }
@progress.size > 0
#=> true

## to_h works on real report
h = @report.to_h
h[:model_class].end_with?('HealthCheckModel')
#=> true

## to_s works on real report
@report.to_s.include?('HealthCheckModel')
#=> true

# Teardown
begin
  existing = Familia.dbclient.keys('health_check_model:*')
  Familia.dbclient.del(*existing) if existing.any?
rescue => e
  # Ignore cleanup errors
end
HealthCheckModel.instances.clear
