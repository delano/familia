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

## takes atomic flags only -- a role symbol raises rather than expanding to its
## bits, since permission? tests bits individually and would answer "holds any"
## where the caller means "holds all"
@target.widgets_with_permission(:editor)
#=!> error.class == ArgumentError

## :admin names a flag as well as a role, so it resolves to bit 7 and does not raise
@target.widgets_with_permission(:admin)
#=> ["w_admin"]

## Issue #309: limit: returns at most N matching members
@target.widgets_with_permission(:read, limit: 2).size
#=> 2

## limit: 0 returns an empty array
@target.widgets_with_permission(:read, limit: 0)
#=> []

## limit greater than the number of matches returns all matches
@target.widgets_with_permission(:read, limit: 10).sort
#=> ["w_admin", "w_read", "w_write"]

## offset is applied POST-FILTER: limit+offset pages walk all matches
## without gaps or overlap (union of the two pages == the unpaged result)
page1 = @target.widgets_with_permission(:read, limit: 2, offset: 0)
page2 = @target.widgets_with_permission(:read, limit: 2, offset: 2)
(page1 + page2).sort
#=> ["w_admin", "w_read", "w_write"]

## offset beyond the number of matches returns an empty array
@target.widgets_with_permission(:read, offset: 10)
#=> []

## small batch_size pages internally but returns the same results as the
## default call (page boundary lands mid-matches: 3 members, pages of 2)
@target.widgets_with_permission(:read, batch_size: 2).sort
#=> ["w_admin", "w_read", "w_write"]

## batch_size pagination with a sparser filter still finds the match
@target.widgets_with_permission(:write, batch_size: 2)
#=> ["w_write"]

## batch_size must be a positive integer
@target.widgets_with_permission(:read, batch_size: 0)
#=!> error.class == ArgumentError

## offset must be non-negative
@target.widgets_with_permission(:read, offset: -1)
#=!> error.class == ArgumentError

## limit must be nil or non-negative
@target.widgets_with_permission(:read, limit: -1)
#=!> error.class == ArgumentError

## Issue #309: the sorted_set participation also generates a ZSCAN-streaming
## each_*_with_permission sibling
@target.respond_to?(:each_widgets_with_permission)
#=> true

## without a block it returns an Enumerator
@target.each_widgets_with_permission(:read).class
#=> Enumerator

## with a block it yields matching members (ZSCAN order is not guaranteed,
## so compare sorted)
collected = []
@target.each_widgets_with_permission(:read) { |m| collected << m }
collected.sort
#=> ["w_admin", "w_read", "w_write"]

## the enumerator filters by permission like the array form
@target.each_widgets_with_permission(:write).to_a
#=> ["w_write"]

## the enumerator is lazy: first(1) yields a single matching member
@target.each_widgets_with_permission(:read).first(1).size
#=> 1

## small batch_size still yields every match exactly (no rehash mid-scan here)
@target.each_widgets_with_permission(:read, batch_size: 1).to_a.sort
#=> ["w_admin", "w_read", "w_write"]

## invalid batch_size raises even without a block
@target.each_widgets_with_permission(:read, batch_size: 0)
#=!> error.class == ArgumentError

@target.widgets.delete!
@target.destroy!
