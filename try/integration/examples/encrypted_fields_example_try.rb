# try/integration/examples/encrypted_fields_example_try.rb
#
# frozen_string_literal: true

# Regression coverage for examples/encrypted_fields.rb.
#
# The examples/ directory had zero automated coverage and rotted unnoticed
# (see issue #250): every ConcealedString#reveal call used string
# interpolation without the required block, the configured keys were 28/29
# bytes instead of 32, and the request-cache + benchmark paths hit latent
# library bugs. This test runs the script end-to-end as a subprocess and
# asserts it completes, so the same class of breakage cannot regress
# silently again.

require 'open3'

require_relative '../../support/helpers/test_helpers'

@root = File.expand_path('../../..', __dir__)
@script = File.join(@root, 'examples', 'encrypted_fields.rb')

@raw_output, @status = Bundler.with_unbundled_env do
  Open3.capture2e('bundle', 'exec', 'ruby', @script, chdir: @root)
end
# Subprocess output contains UTF-8 glyphs; normalize so string matching does
# not blow up under a US-ASCII default external encoding.
@output = @raw_output.to_s.dup.force_encoding('UTF-8').scrub
@exit_code = @status.exitstatus

## Script file exists
File.exist?(@script)
#=> true

## Runs top-to-bottom with a zero exit status
[@exit_code, @output.lines.last.to_s.strip]
#=> [0, 'Encrypted Fields examples completed!']

## Reveal block form returns plaintext in interpolation (sites 1-7)
@output.include?('SSN (encrypted): ConcealedString -> 123-45-6789')
#=> true

## AAD-protected content reveals correctly (sites 4-5)
@output.include?('Content (with AAD protection): This document contains sensitive strategic information...')
#=> true

## Bare reveal in a rescue raises the real EncryptionError, not ArgumentError (site 8)
@output.include?('Caught expected error with missing key version')
#=> true

## Reveal inside a safe_dump lambda masks the phone (site 9)
@output.include?('"phone_display": "555-***-4567"')
#=> true

## Benchmark path works (xchacha20 provider no longer mutates a frozen context)
@output.include?('Encryption benchmark results (100 iterations):')
#=> true

## No Ruby exception leaked to stderr/stdout
@output.match?(/ArgumentError|FrozenError|NoMethodError|\(NameError\)/)
#=> false

## Cleanup actually deletes created keys (locks in the config_name prefix fix)
# SecureUser persists records in Examples 1 and 6, so a correct prefix must
# delete a non-zero key count. The old wrong prefix (secureuser:* vs
# secure_user:*) reported "(0 keys)", so a zero count must fail this test.
@output[/Cleaned SecureUser \((\d+) keys\)/, 1].to_i.positive?
#=> true
