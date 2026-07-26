# try/integration/examples/relationships_example_try.rb
#
# frozen_string_literal: true

# Regression coverage for examples/relationships.rb.
#
# This script was fully non-functional (see issue #250): it called the
# renamed-away class_indexed_by/get_by_* APIs and crashed at class-definition
# time. It now uses the current v2 DSL (unique_index / multi_index /
# participates_in / class_participates_in / instances). Because unique_index
# enforces uniqueness, a broken teardown would make the script crash with
# RecordExistsError on the next run, so this test runs it twice to guard
# both correctness and idempotency.

require 'open3'

require_relative '../../support/helpers/test_helpers'

@root = File.expand_path('../../..', __dir__)
@script = File.join(@root, 'examples', 'relationships.rb')

def run_relationships_example(root, script)
  out, status = Bundler.with_unbundled_env do
    Open3.capture2e('bundle', 'exec', 'ruby', script, chdir: root)
  end
  # Normalize to UTF-8 so matching the script's glyph-laden output does not
  # raise under a US-ASCII default external encoding.
  [out.to_s.dup.force_encoding('UTF-8').scrub, status]
end

@output, @status = run_relationships_example(@root, @script)
@exit_code = @status.exitstatus

## Script file exists
File.exist?(@script)
#=> true

## Runs top-to-bottom with a zero exit status
[@exit_code, @output.lines.last.to_s.strip]
#=> [0, 'See docs/wiki/Relationships-Guide.md for comprehensive documentation']

## unique_index generates find_by_<field> returning a single record
@output.match?(/Email lookup \(unique_index\): cust_/)
#=> true

# Count-based markers use >= thresholds rather than exact values: in the
# full suite other tests may also write to db 15, so the example's own
# records are a lower bound, not the only contents.

## multi_index find_all_by_plan returns at least the example's enterprise customer
@output[/Plan lookup \(multi_index\): (\d+) enterprise customer/, 1].to_i >= 1
#=> true

## class_participates_in active_domains holds at least the two added domains
@output[/Active domains in system: (\d+)/, 1].to_i >= 2
#=> true

## Built-in instances timeline rangebyscore returns at least the example's customer
@output[/Recent customers \(last 24h\): (\d+)/, 1].to_i >= 1
#=> true

## Did not crash on the renamed-away class_indexed_by / get_by_* APIs
@output.match?(/undefined method [`']class_indexed_by'|undefined method [`']get_by_/)
#=> false

## Second consecutive run also succeeds (teardown makes it idempotent)
@output2, status2 = run_relationships_example(@root, @script)
[status2.exitstatus, @output2.include?('RecordExistsError')]
#=> [0, false]
