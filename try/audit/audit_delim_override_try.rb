# try/audit/audit_delim_override_try.rb
#
# frozen_string_literal: true
#
# Regression coverage for audit SCAN patterns under a non-default
# Familia.delim. Exercises the three audit entry points that construct
# SCAN patterns by interpolating the delim:
#
#   - discover_multi_index_buckets (audit_multi_indexes)
#   - audit_instance_participations (audit_participations)
#   - audit_single_related_field (audit_related_fields)
#
# With a hardcoded ":" separator these SCAN patterns match zero keys when
# a deployment overrides Familia.delim, silently reporting a clean audit.
# Each testcase flips the delim to "|" for the duration of its own setup,
# asserts a single behavior, then restores the original delim in an
# ensure block. Tryouts v3 shares context across testcases within a file
# by default, so the ensure block is critical to prevent bleed into the
# rest of the suite.
#
# Setup is inline per testcase (not cumulative) so each case is fully
# self-contained. Cleanup operates under whichever delim created the
# keys, since key names in Redis are literal strings that do not change
# when Familia.delim is reconfigured later.

require_relative '../support/helpers/test_helpers'

# Participation target for the instance-level participation case.
class DelimAuditCustomer < Familia::Horreum
  feature :relationships

  identifier_field :cid
  field :cid
  field :name

  sorted_set :domains
end

# Participant + multi-index + related-field model used across the tests.
class DelimAuditModel < Familia::Horreum
  feature :relationships

  identifier_field :oid
  field :oid
  field :role
  field :created_at

  list :sessions

  multi_index :role, :role_index

  participates_in DelimAuditCustomer, :domains, score: :created_at
end

# Delete every Redis key under BOTH the custom delim ("|") and the default
# delim (":") for the two model prefixes. Used in every testcase's ensure
# block so no residue can leak across testcases or into other test files.
#
# Also clears the class-level instances ZSET under whichever delim is
# currently configured, so the ZSET key the Familia DSL resolves for
# `.instances` matches the one on disk.
def dadelim_full_cleanup
  %w[delim_audit_customer delim_audit_model].each do |prefix|
    %w[: |].each do |sep|
      keys = Familia.dbclient.keys("#{prefix}#{sep}*")
      Familia.dbclient.del(*keys) if keys.any?
    end
  end
rescue StandardError
  # swallow cleanup errors - they are not what we are testing
end

# Save the original delim ONCE at the top of the file. Every testcase
# restores to this value in its ensure block. Keeping it as a local
# constant means tryouts shared-context cannot accidentally overwrite it.
ORIGINAL_DELIM = Familia.delim

## Multi-index: healthy baseline under custom delim has clean audit
# Covers the full audit_multi_indexes flow under a non-default delim:
# bucket SCAN discovers the per-value keys (discover_multi_index_buckets)
# AND scan_identifiers (via Horreum.scan_pattern) returns the live objects
# so the missing/orphaned phases can correlate buckets to real instances.
# Three live objects across two distinct role values produce two buckets,
# both of which correspond to live instances, so the audit should be clean.
begin
  dadelim_full_cleanup
  Familia.delim = '|'
  m1 = DelimAuditModel.new(oid: 'da-1', role: 'admin', created_at: 1)
  m1.save
  m2 = DelimAuditModel.new(oid: 'da-2', role: 'admin', created_at: 2)
  m2.save
  m3 = DelimAuditModel.new(oid: 'da-3', role: 'member', created_at: 3)
  m3.save
  result = DelimAuditModel.audit_multi_indexes.first
  [result[:status], result[:stale_members], result[:missing], result[:orphaned_keys]]
ensure
  dadelim_full_cleanup
  Familia.delim = ORIGINAL_DELIM
end
#=> [:ok, [], [], []]

## Multi-index: orphaned bucket under custom delim is detected
# Regression guard for discover_multi_index_buckets. Without the
# Familia.delim interpolation (fixed in d6a651b) the SCAN pattern matches
# no keys and the orphan bucket silently disappears from the audit.
begin
  dadelim_full_cleanup
  Familia.delim = '|'
  live = DelimAuditModel.new(oid: 'da-live', role: 'admin', created_at: 10)
  live.save
  orphan_key = "#{DelimAuditModel.prefix}|role_index|ghost"
  Familia.dbclient.sadd(orphan_key, '"phantom"')
  result = DelimAuditModel.audit_multi_indexes.first
  [result[:status],
   result[:orphaned_keys].any? { |o| o[:field_value] == 'ghost' && o[:key] == orphan_key }]
ensure
  dadelim_full_cleanup
  Familia.delim = ORIGINAL_DELIM
end
#=> [:issues_found, true]

## Participation: stale instance-level member under custom delim is detected
# Regression guard for audit_instance_participations (line 690). The SCAN
# pattern "#{target.prefix}:*:#{collection_name}" was hardcoded so under
# a custom delim it matched no customer-domains keys and the audit
# returned an empty stale_members list for every relationship.
begin
  dadelim_full_cleanup
  Familia.delim = '|'
  cust = DelimAuditCustomer.new(cid: 'dac-1', name: 'Acme')
  cust.save
  dom_live = DelimAuditModel.new(oid: 'ddl-1', role: 'admin', created_at: 100)
  dom_live.save
  dom_dead = DelimAuditModel.new(oid: 'ddl-2', role: 'admin', created_at: 101)
  dom_dead.save
  cust.add_domains_instance(dom_live)
  cust.add_domains_instance(dom_dead)
  # Delete the hash key directly so the participant lingers in the
  # customer's domains sorted set without a backing object.
  Familia.dbclient.del(dom_dead.dbkey)
  audit = DelimAuditModel.audit_participations
  total_stale = audit.sum { |r| r[:stale_members].size }
  stale_entry = audit.flat_map { |r| r[:stale_members] }.find { |m| m[:identifier] == 'ddl-2' }
  [total_stale, stale_entry && stale_entry[:reason]]
ensure
  dadelim_full_cleanup
  Familia.delim = ORIGINAL_DELIM
end
#=> [1, :object_missing]

## Related fields: orphaned list key under custom delim is detected
# Regression guard for audit_single_related_field. The SCAN pattern for
# "#{prefix}{delim}*{delim}{field_name}" is correct on main, but this
# testcase ensures the fix does not regress and confirms SCAN still
# picks up orphans when the middle separator is "|" rather than ":".
begin
  dadelim_full_cleanup
  Familia.delim = '|'
  obj = DelimAuditModel.new(oid: 'dar-crashed', role: 'admin', created_at: 1)
  obj.save
  obj.sessions.push('session-1')
  # Delete the parent hash key; the sessions list key remains orphaned.
  Familia.dbclient.del(obj.dbkey)
  sessions_result = DelimAuditModel.audit_related_fields.find { |r| r[:field_name] == :sessions }
  [sessions_result[:status],
   sessions_result[:orphaned_keys],
   sessions_result[:count]]
ensure
  dadelim_full_cleanup
  Familia.delim = ORIGINAL_DELIM
end
#=> [:issues_found, ["delim_audit_model|dar-crashed|sessions"], 1]

## Delim is restored to the original value between testcases
# Paranoia guard: if any prior testcase forgot its ensure block the rest
# of the suite would see the wrong delim. This asserts the invariant
# without constructing any keys.
Familia.delim
#=> ORIGINAL_DELIM

# Teardown: belt-and-braces cleanup. All four testcases clean up in
# their own ensure blocks, but run one more sweep in case a testcase
# died between save and ensure.
dadelim_full_cleanup
Familia.delim = ORIGINAL_DELIM
