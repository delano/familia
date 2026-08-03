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

# Empty collection: min_permission must be validated eagerly, since the lazy
# per-member permission? check never runs when there is nothing to scan.
@empty_target = PermTarget.new(tid: "perm_target_empty", name: "E")
@empty_target.save
@empty_target.widgets.delete!

# Multi-page dataset: 12 members with distinct integer-second timestamps so
# ZRANGEBYSCORE order is deterministic. :write is set on m01-m04 and m09-m12;
# m05-m08 are read-only, so with batch_size: 4 the middle page is entirely
# non-matching for :write and must be skipped by the paging loop.
@paged_target = PermTarget.new(tid: "perm_target_paged", name: "P")
@paged_target.save
@paged_target.widgets.delete!
base = Familia.now.to_i
(1..12).each do |i|
  flags = (5..8).cover?(i) ? [:read] : [:read, :write]
  @paged_target.widgets.add(format("m%02d", i), SE.encode_score(base + i, flags))
end

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

## min_permission is validated eagerly: a role raises even with limit: 0,
## which would otherwise short-circuit to [] before any per-member check
@target.widgets_with_permission(:editor, limit: 0)
#=!> error.class == ArgumentError

## eager validation also fires on an EMPTY collection (array form), where the
## lazy per-member check would never run
@empty_target.widgets_with_permission(:editor)
#=!> error.class == ArgumentError

## unknown permission symbols raise on an empty collection too
@empty_target.widgets_with_permission(:bogus)
#=!> error.class == ArgumentError

## the streaming form validates min_permission eagerly on an empty collection
@empty_target.each_widgets_with_permission(:editor) { |m| m }
#=!> error.class == ArgumentError

## and even without a block, before the Enumerator is built
@empty_target.each_widgets_with_permission(:editor)
#=!> error.class == ArgumentError

## multi-page boundary: batch_size: 4 over 12 members pages through an
## entirely non-matching middle page (m05-m08 lack :write) without dropping
## the matches on either side
@paged_target.widgets_with_permission(:write, batch_size: 4)
#=> ["m01", "m02", "m03", "m04", "m09", "m10", "m11", "m12"]

## the paged result equals the default (unpaged) result
@paged_target.widgets_with_permission(:write, batch_size: 4) == @paged_target.widgets_with_permission(:write)
#=> true

## limit + offset + batch_size combined: offset is POST-FILTER, so it skips
## the first 3 :write matches (m01-m03), then limit: 3 takes m04 plus the two
## matches after the non-matching middle page
@paged_target.widgets_with_permission(:write, limit: 3, offset: 3, batch_size: 4)
#=> ["m04", "m09", "m10"]

## same kwarg combination where every member matches (:read): the window is a
## straight slice of score order across internal page boundaries
@paged_target.widgets_with_permission(:read, limit: 5, offset: 4, batch_size: 4)
#=> ["m05", "m06", "m07", "m08", "m09"]

@target.widgets.delete!
@target.destroy!
@empty_target.destroy!
@paged_target.widgets.delete!
@paged_target.destroy!
