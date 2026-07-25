# try/features/relationships/score_encoding_permissions_try.rb
#
# frozen_string_literal: true

# Permission API surface of ScoreEncoding: add/remove/query permission bits
# encoded in the fractional part of sorted set scores.
#
# Regression focus: symbol->flag lookups previously fell back to `|| 0`, so a
# mistyped symbol (e.g. :admn) was a silent no-op — remove_permissions LEFT the
# permission granted. All lookups now route through permission_level_value and
# raise ArgumentError on unknown symbols. :none (0) remains a valid flag.
#
# category_score_range was removed entirely: a bitmask category is not
# expressible as one contiguous score range (see try/bug_fixes/
# permission_query_try.rb). Use score_range + filter_by_category instead.

require_relative '../../support/helpers/test_helpers'

@se = Familia::Features::Relationships::ScoreEncoding
@ts = 1_704_067_200
@read_score = @se.encode_score(@ts, [:read])                  # bits 1
@full_score = @se.encode_score(@ts, [:read, :write, :delete]) # bits 37
@mixed_scores = [
  @se.encode_score(@ts, [:read]),
  @se.encode_score(@ts, [:read, :write]),
  @se.encode_score(@ts, [:read, :admin]),
]

## add_permissions adds new flags to an existing score
@se.decode_score(@se.add_permissions(@read_score, :write, :delete))[:permission_list]
#=> [:read, :write, :delete]

## add_permissions preserves the timestamp portion
@se.decode_score(@se.add_permissions(@read_score, :write))[:timestamp]
#=> 1_704_067_200

## add_permissions with :none is a valid no-op
@se.decode_score(@se.add_permissions(@read_score, :none))[:permissions]
#=> 1

## add_permissions raises on an unknown permission symbol
@se.add_permissions(@read_score, :admn)
#=!> error.class == ArgumentError
#=!> error.message.include?('Unknown permission')

## remove_permissions removes only the named flag and keeps the others
@se.decode_score(@se.remove_permissions(@full_score, :write))[:permission_list]
#=> [:read, :delete]

## remove_permissions with :none is a valid no-op
@se.decode_score(@se.remove_permissions(@full_score, :none))[:permissions]
#=> 37

## remove_permissions raises on an unknown symbol instead of silently
## leaving the permission granted
@se.remove_permissions(@full_score, :admn)
#=!> error.class == ArgumentError

## encode_score still accepts role symbols (editor = read|write|edit)
@se.decode_score(@se.encode_score(@ts, :editor))[:permissions]
#=> 13

## encode_score raises on an unknown permission symbol
@se.encode_score(@ts, :bogus)
#=!> error.class == ArgumentError

## encode_score raises when an array contains an unknown symbol
@se.encode_score(@ts, [:read, :bogus])
#=!> error.class == ArgumentError

## permission? raises on an unknown symbol
@se.permission?(@read_score, :bogus)
#=!> error.class == ArgumentError

## permission_tier classifies admin bits as :administrator
@se.permission_tier(@se.encode_score(@ts, [:read, :admin]))
#=> :administrator

## permission_tier classifies content bits as :content_editor
@se.permission_tier(@se.encode_score(@ts, [:read, :write]))
#=> :content_editor

## permission_tier classifies read-only as :viewer
@se.permission_tier(@read_score)
#=> :viewer

## permission_tier classifies zero bits as :none
@se.permission_tier(@se.encode_score(@ts, 0))
#=> :none

## meets_category? :readable is true for any permission bits
@se.meets_category?(1, :readable)
#=> true

## meets_category? :privileged is false for read-only bits
@se.meets_category?(1, :privileged)
#=> false

## meets_category? :privileged is true beyond read-only
@se.meets_category?(5, :privileged)
#=> true

## meets_category? :administrator matches bits in the admin mask
@se.meets_category?(0b10000000, :administrator)
#=> true

## meets_category? :administrator is false for content-only bits
@se.meets_category?(0b00000111, :administrator)
#=> false

## meets_category? returns false for unknown categories
@se.meets_category?(255, :bogus)
#=> false

## filter_by_category keeps only scores whose bits match the category mask
@se.filter_by_category(@mixed_scores, :administrator).map { |s| @se.decode_score(s)[:permissions] }
#=> [129]

## categorize_scores groups scores by permission tier
@se.categorize_scores(@mixed_scores).keys.sort
#=> [:administrator, :content_editor, :viewer]

## permission_range returns fractional min/max bits
@se.permission_range([:read], [:read, :write])
#=> [0.001, 0.005]

## permission_range defaults max to all bits (255)
@se.permission_range([:read])
#=> [0.001, 0.255]

## permission_range raises on unknown symbols
@se.permission_range([:bogus])
#=!> error.class == ArgumentError

## category_score_range is gone: a bitmask category cannot be one
## contiguous score range
@se.respond_to?(:category_score_range)
#=> false
