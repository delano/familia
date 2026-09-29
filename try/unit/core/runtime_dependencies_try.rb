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

# An application's bundle can resolve any release a requirement allows, so
# each floor must exclude releases that load a library leaving Ruby's
# default gems (the SINCE table in Ruby's bundled_gems.rb) without declaring
# it. Under Bundler, requiring such a library raises LoadError on the Ruby
# version the table lists for it and later. Ruby 3.4 also warns when it
# loads a library listed at 4.0.0 from the standard library. So on Ruby 3.4,
# bigdecimal and base64 (listed at 3.4.0) raise LoadError, and ostruct
# (listed at 4.0.0) loads with a warning.
# From each release's gemspec and lib/:
# - oj 3.16.0 to 3.16.4 require bigdecimal (lib/oj/mimic.rb) and ostruct
#   (lib/oj/mimic.rb, which rescues its failure, and lib/oj/json.rb).
#   3.16.0 and 3.16.1 declare neither, so they raise LoadError on Ruby 3.4.
#   3.16.2 to 3.16.4 declare only bigdecimal, so they warn about ostruct on
#   Ruby 3.4. 3.16.5 declares both.
# - json_schemer 2.0.0 to 2.1.1 require base64 and bigdecimal
#   (lib/json_schemer.rb) and declare neither. 2.2.0 declares both.

## oj's requirement excludes the releases that load ostruct or bigdecimal without declaring it
oj = @gemspec.runtime_dependencies.find { |dep| dep.name == 'oj' }
%w[3.16.1 3.16.4 3.16.5].map { |version| oj.requirement.satisfied_by?(Gem::Version.new(version)) }
#=> [false, false, true]

## json_schemer's requirement excludes the releases that load base64 and bigdecimal without declaring them
json_schemer = @gemspec.runtime_dependencies.find { |dep| dep.name == 'json_schemer' }
%w[2.0.0 2.1.1 2.2.0].map { |version| json_schemer.requirement.satisfied_by?(Gem::Version.new(version)) }
#=> [false, false, true]
