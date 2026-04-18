# try/audit/audit_related_fields_try.rb
#
# frozen_string_literal: true

# audit_related_fields: detects orphaned DataType collection keys whose
# parent Horreum hash no longer exists. Covers healthy baselines, single
# and multiple field orphans, mixed live+crashed state, compound
# identifiers, opt-in health_check wiring, and the class-level skip.

require_relative '../support/helpers/test_helpers'

class ARFPlainModel < Familia::Horreum
  identifier_field :pid
  field :pid
  field :name
end

class ARFWithCollections < Familia::Horreum
  identifier_field :cid
  field :cid
  field :name
  list :sessions
  set :tags
  hashkey :settings
end

class ARFCompoundId < Familia::Horreum
  identifier_field :cid
  field :cid
  field :name
  list :sessions
end

class ARFClassOnly < Familia::Horreum
  identifier_field :cid
  field :cid
  field :name
  list :sessions
  class_list :audit_log
end

def arf_reset_model(klass)
  existing = Familia.dbclient.keys("#{klass.prefix}:*")
  Familia.dbclient.del(*existing) if existing.any?
rescue StandardError
  # ignore cleanup errors
ensure
  klass.instances.clear if klass.respond_to?(:instances)
end

## audit_related_fields on class without relations returns empty array
arf_reset_model(ARFPlainModel)
ARFPlainModel.audit_related_fields
#=> []

## audit_related_fields always returns an Array
arf_reset_model(ARFPlainModel)
ARFPlainModel.audit_related_fields.is_a?(Array)
#=> true

## Healthy baseline: three instances with populated collections produce no orphans
arf_reset_model(ARFWithCollections)
@h1 = ARFWithCollections.new(cid: 'hc-1', name: 'One')
@h1.save
@h1.sessions.push('session-1')
@h1.tags.add('admin')
@h1.settings['theme'] = 'dark'
@h2 = ARFWithCollections.new(cid: 'hc-2', name: 'Two')
@h2.save
@h2.sessions.push('session-2')
@h2.tags.add('user')
@h2.settings['lang'] = 'en'
@h3 = ARFWithCollections.new(cid: 'hc-3', name: 'Three')
@h3.save
@h3.sessions.push('session-3')
@h3.tags.add('member')
@h3.settings['tz'] = 'utc'
@results = ARFWithCollections.audit_related_fields
@results.size
#=> 3

## Healthy baseline: each result has status :ok
arf_reset_model(ARFWithCollections)
@h1 = ARFWithCollections.new(cid: 'hc-1', name: 'One')
@h1.save
@h1.sessions.push('session-1')
@h1.tags.add('admin')
@h1.settings['theme'] = 'dark'
ARFWithCollections.audit_related_fields.all? { |r| r[:status] == :ok }
#=> true

## Healthy baseline: each result has empty orphaned_keys
arf_reset_model(ARFWithCollections)
@h1 = ARFWithCollections.new(cid: 'hc-1', name: 'One')
@h1.save
@h1.sessions.push('session-1')
@h1.tags.add('admin')
@h1.settings['theme'] = 'dark'
ARFWithCollections.audit_related_fields.all? { |r| r[:orphaned_keys].empty? && r[:count].zero? }
#=> true

## Healthy baseline: result includes field_name for each declared field
arf_reset_model(ARFWithCollections)
@h1 = ARFWithCollections.new(cid: 'hc-1', name: 'One')
@h1.save
@h1.sessions.push('session-1')
@h1.tags.add('admin')
@h1.settings['theme'] = 'dark'
ARFWithCollections.audit_related_fields.map { |r| r[:field_name] }.sort
#=> [:sessions, :settings, :tags]

## Healthy baseline: klass is reported as a String
arf_reset_model(ARFWithCollections)
@h1 = ARFWithCollections.new(cid: 'hc-1', name: 'One')
@h1.save
@h1.sessions.push('session-1')
@sessions_result = ARFWithCollections.audit_related_fields.find { |r| r[:field_name] == :sessions }
@sessions_result[:klass].is_a?(String)
#=> true

## Orphan via direct hash deletion: list key is reported as orphaned
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
@result = ARFWithCollections.audit_related_fields.find { |r| r[:field_name] == :sessions }
@result[:orphaned_keys]
#=> ["arf_with_collections:crashed:sessions"]

## Orphan via direct hash deletion: status is :issues_found
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
@result = ARFWithCollections.audit_related_fields.find { |r| r[:field_name] == :sessions }
@result[:status]
#=> :issues_found

## Orphan via direct hash deletion: count reflects orphan count
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
@result = ARFWithCollections.audit_related_fields.find { |r| r[:field_name] == :sessions }
@result[:count]
#=> 1

## Multiple field types orphaned: list, set, and hashkey all reported
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'multi', name: 'Multi')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
@obj.settings['k'] = 'v'
Familia.dbclient.del(@obj.dbkey)
@results = ARFWithCollections.audit_related_fields
@results.all? { |r| r[:orphaned_keys].size == 1 && r[:status] == :issues_found }
#=> true

## Multiple field types orphaned: each orphan key carries the correct field suffix
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'multi', name: 'Multi')
@obj.save
@obj.sessions.push('s-1')
@obj.tags.add('t-1')
@obj.settings['k'] = 'v'
Familia.dbclient.del(@obj.dbkey)
@results = ARFWithCollections.audit_related_fields
@results.all? { |r| r[:orphaned_keys].first.end_with?(":#{r[:field_name]}") }
#=> true

## Mixed live + orphaned: only crashed instances are reported
arf_reset_model(ARFWithCollections)
@live = ARFWithCollections.new(cid: 'alive', name: 'Alive')
@live.save
@live.sessions.push('live-session')
@dead = ARFWithCollections.new(cid: 'dead', name: 'Dead')
@dead.save
@dead.sessions.push('dead-session')
Familia.dbclient.del(@dead.dbkey)
@sessions_result = ARFWithCollections.audit_related_fields.find { |r| r[:field_name] == :sessions }
@sessions_result[:orphaned_keys]
#=> ["arf_with_collections:dead:sessions"]

## Mixed live + orphaned: non-crashed instance's collection key is not reported
arf_reset_model(ARFWithCollections)
@live = ARFWithCollections.new(cid: 'alive', name: 'Alive')
@live.save
@live.sessions.push('live-session')
@dead = ARFWithCollections.new(cid: 'dead', name: 'Dead')
@dead.save
@dead.sessions.push('dead-session')
Familia.dbclient.del(@dead.dbkey)
@sessions_result = ARFWithCollections.audit_related_fields.find { |r| r[:field_name] == :sessions }
@sessions_result[:orphaned_keys].any? { |k| k.include?(':alive:') }
#=> false

## Compound identifier with colons: orphan detection works
arf_reset_model(ARFCompoundId)
@compound = ARFCompoundId.new(cid: 'part1:part2', name: 'Compound')
@compound.save
@compound.sessions.push('compound-session')
Familia.dbclient.del(@compound.dbkey)
@result = ARFCompoundId.audit_related_fields.find { |r| r[:field_name] == :sessions }
@result[:orphaned_keys]
#=> ["arf_compound_id:part1:part2:sessions"]

## Compound identifier: status :issues_found
arf_reset_model(ARFCompoundId)
@compound = ARFCompoundId.new(cid: 'part1:part2', name: 'Compound')
@compound.save
@compound.sessions.push('compound-session')
Familia.dbclient.del(@compound.dbkey)
ARFCompoundId.audit_related_fields.find { |r| r[:field_name] == :sessions }[:status]
#=> :issues_found

## Compound identifier: live compound id produces no orphan
arf_reset_model(ARFCompoundId)
@compound = ARFCompoundId.new(cid: 'part1:part2', name: 'Compound')
@compound.save
@compound.sessions.push('compound-session')
ARFCompoundId.audit_related_fields.find { |r| r[:field_name] == :sessions }[:orphaned_keys]
#=> []

## health_check default does not include related_fields audit
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
@report = ARFWithCollections.health_check
@report.related_fields
#=> nil

## health_check default: complete? is false because related_fields was skipped
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'default-skip', name: 'Skip')
@obj.save
ARFWithCollections.health_check.complete?
#=> false

## health_check with audit_collections: true includes related_fields
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
@report = ARFWithCollections.health_check(audit_collections: true)
@report.related_fields.is_a?(Array)
#=> true

## health_check with audit_collections: true surfaces orphans
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
@report = ARFWithCollections.health_check(audit_collections: true)
@report.related_fields.any? { |r| r[:status] == :issues_found }
#=> true

## health_check with audit_collections: true makes the report unhealthy when orphans exist
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'crashed', name: 'Crashed')
@obj.save
@obj.sessions.push('s-1')
Familia.dbclient.del(@obj.dbkey)
# Also clean up the phantom from instances to isolate the collection-orphan signal.
ARFWithCollections.instances.remove('crashed')
ARFWithCollections.health_check(audit_collections: true).healthy?
#=> false

## health_check with audit_collections: true on clean state: complete? is true
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'clean', name: 'Clean')
@obj.save
@obj.sessions.push('s-1')
ARFWithCollections.health_check(audit_collections: true, check_cross_refs: true).complete?
#=> true

## health_check with audit_collections: true on clean state: healthy? is true
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'clean', name: 'Clean')
@obj.save
@obj.sessions.push('s-1')
ARFWithCollections.health_check(audit_collections: true).healthy?
#=> true

## Class-level related_fields are not reported as orphans
arf_reset_model(ARFClassOnly)
ARFClassOnly.audit_log.push('entry-1')
ARFClassOnly.audit_log.push('entry-2')
@results = ARFClassOnly.audit_related_fields
@results.size
#=> 1

## Class-level related_fields: only the instance-level :sessions field audited
arf_reset_model(ARFClassOnly)
ARFClassOnly.audit_log.push('entry-1')
ARFClassOnly.audit_related_fields.first[:field_name]
#=> :sessions

## Class-level related_fields: class-level collection key is never reported as orphaned
arf_reset_model(ARFClassOnly)
ARFClassOnly.audit_log.push('entry-1')
ARFClassOnly.audit_log.push('entry-2')
@class_key = ARFClassOnly.audit_log.dbkey
ARFClassOnly.audit_related_fields.none? { |r| r[:orphaned_keys].include?(@class_key) }
#=> true

## to_h includes related_fields as nil when not checked
arf_reset_model(ARFWithCollections)
ARFWithCollections.health_check.to_h[:related_fields]
#=> nil

## to_h includes related_fields summary when checked
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'clean', name: 'Clean')
@obj.save
@obj.sessions.push('s-1')
ARFWithCollections.health_check(audit_collections: true).to_h[:related_fields].is_a?(Array)
#=> true

## to_s mentions related_fields not_checked when skipped
arf_reset_model(ARFWithCollections)
ARFWithCollections.health_check.to_s.include?('not_checked')
#=> true

## to_s mentions related_field entry when checked
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'clean', name: 'Clean')
@obj.save
@obj.sessions.push('s-1')
ARFWithCollections.health_check(audit_collections: true).to_s.include?('related_field :sessions')
#=> true

## related_fields entry carries exactly the documented key shape
# audit_related_fields returns entries with {:field_name, :klass, :orphaned_keys, :count, :status}.
# Test against report.related_fields (the raw array) since to_h collapses orphaned_keys to a count.
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'clean', name: 'Clean')
@obj.save
@obj.sessions.push('s-1')
@report = ARFWithCollections.health_check(audit_collections: true)
@entry = @report.related_fields.first
@entry.keys.sort
#=> [:count, :field_name, :klass, :orphaned_keys, :status]

## complete? is false when audit_collections: true but check_cross_refs is left off
arf_reset_model(ARFWithCollections)
@obj = ARFWithCollections.new(cid: 'cr-off', name: 'NoCR')
@obj.save
@obj.sessions.push('s-1')
ARFWithCollections.health_check(audit_collections: true).complete?
#=> false

# Teardown
arf_reset_model(ARFPlainModel)
arf_reset_model(ARFWithCollections)
arf_reset_model(ARFCompoundId)
arf_reset_model(ARFClassOnly)
