# try/integration/examples/safe_dump_example_try.rb
#
# frozen_string_literal: true

# Regression coverage for examples/safe_dump.rb.
#
# The teardown passed an unsplatted array to `del` with no empty guard and
# used the wrong key prefix (see issue #250), so it never actually cleaned
# up and would misbehave on non-tolerant clients. This test runs the script
# twice and asserts it completes and leaves no leftover keys, locking in the
# splat + empty-guard + config_name prefix fix.

require 'open3'

require_relative '../../support/helpers/test_helpers'

@root = File.expand_path('../../..', __dir__)
@script = File.join(@root, 'examples', 'safe_dump.rb')

def run_safe_dump_example(root, script)
  out, status = Bundler.with_unbundled_env do
    Open3.capture2e('bundle', 'exec', 'ruby', script, chdir: root)
  end
  # Normalize to UTF-8 so matching the script's glyph-laden output does not
  # raise under a US-ASCII default external encoding.
  [out.to_s.dup.force_encoding('UTF-8').scrub, status]
end

@output, @status = run_safe_dump_example(@root, @script)
@exit_code = @status.exitstatus

## Script file exists
File.exist?(@script)
#=> true

## Runs top-to-bottom with a zero exit status
[@exit_code, @output.lines.last.to_s.strip]
#=> [0, 'SafeDump examples completed!']

## Computed safe_dump fields render
@output.include?('Example 2: SafeDump with computed fields')
#=> true

## Nested object safe_dump renders the billing address
@output.include?('"billing_address"')
#=> true

## Teardown raised no "Error cleaning" message (splat + empty guard works)
@output.include?('Error cleaning')
#=> false

# A second consecutive run must also succeed and report no cleaning error.
# We assert on the script's own output rather than scanning the shared
# example db: in the full suite many other tests write to db 3, so a global
# key scan is not a meaningful idempotency signal.

## Second consecutive run is idempotent: exits 0, completes, no cleaning error
@output2, status2 = run_safe_dump_example(@root, @script)
[status2.exitstatus, @output2.lines.last.to_s.strip, @output2.include?('Error cleaning')]
#=> [0, 'SafeDump examples completed!', false]
