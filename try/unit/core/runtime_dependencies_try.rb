# try/unit/core/runtime_dependencies_try.rb
#
# frozen_string_literal: true

# Every runtime dependency in familia.gemspec lands in the bundle of every
# application that uses familia, so the list holds only gems familia's own
# code needs. Change it deliberately.
#
# Left out on purpose:
# - base64: Familia::Encryption::StrictBase64 uses core Array#pack and
#   String#unpack1 instead.
# - benchmark: Familia::Encryption.benchmark times with
#   Process.clock_gettime instead.
# - connection_pool: familia calls no connection_pool API. Applications that
#   pool connections for Familia.connection_provider require it themselves.
# - pry-byebug, rake: optional. Interactive migrations need the application
#   to bundle pry-byebug, and the migration rake tasks load from the
#   application's Rakefile.

require_relative '../../support/helpers/test_helpers'

@gemspec = Gem::Specification.load(File.expand_path('../../../familia.gemspec', __dir__))

## familia.gemspec declares only the runtime dependencies familia's code needs
@gemspec.runtime_dependencies.map(&:name).sort
#=> %w[concurrent-ruby json_schemer logger oj redis uri-valkey]
