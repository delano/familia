# try/bug_fixes/permission_query_try.rb
#
# frozen_string_literal: true

# Regression: the generated `<collection>_with_permission` query method was dead
# code. It called `collection.zrangebyscore` (SortedSet only defines
# `rangebyscore`) and a fallback `members(with_scores: true)` (members takes a
# positional count), so it raised NoMethodError/ArgumentError unconditionally.
#
# It was also semantically wrong: permission bits live in the fractional part of
# the score and are NOT a contiguous range, so a `[score, +inf]` range query
# matches members regardless of their actual permission bits. Filtering must be
# done per-member via ScoreEncoding.permission?.

require_relative '../support/helpers/test_helpers'

SE = Familia::Features::Relationships::ScoreEncoding

class ::PermTarget < Familia::Horreum
  feature :relationships
  identifier_field :tid
  field :tid
  field :name
end

class ::PermParticipant < Familia::Horreum
  feature :relationships
  identifier_field :pid
  field :pid
  participates_in PermTarget, :widgets, type: :sorted_set
end

@target = PermTarget.new(tid: "perm_target_1", name: "T")
@target.save
@target.widgets.delete!

# Members stored with permission-encoded scores (timestamp.permission_bits)
now = Familia.now
@target.widgets.add("w_read",  SE.encode_score(now, [:read]))            # read
@target.widgets.add("w_write", SE.encode_score(now, [:read, :write]))   # read + write
@target.widgets.add("w_admin", SE.encode_score(now, [:read, :admin]))   # read + admin

## the sorted_set participation generates a *_with_permission method
@target.respond_to?(:widgets_with_permission)
#=> true

## widgets_with_permission(:read) returns every member that has the read bit
@target.widgets_with_permission(:read).sort
#=> ["w_admin", "w_read", "w_write"]

## widgets_with_permission(:write) returns only members with the write bit
@target.widgets_with_permission(:write).sort
#=> ["w_write"]

## widgets_with_permission(:admin) returns only members with the admin bit
@target.widgets_with_permission(:admin)
#=> ["w_admin"]

## defaults to :read when no permission given
@target.widgets_with_permission.sort
#=> ["w_admin", "w_read", "w_write"]

@target.widgets.delete!
@target.destroy!
