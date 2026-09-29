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
# each floor excludes releases that make require 'familia' or schema
# validation fail. Under Bundler, requiring a library that Ruby's
# bundled_gems.rb lists as leaving the default gems raises LoadError on the
# Ruby version listed for it and later, unless the bundle contains it.
# bigdecimal and base64 are listed at 3.4.0.
# From each release's gemspec and lib/:
# - oj 3.16.0 and 3.16.1 declare no runtime dependencies, and lib/oj.rb
#   requires lib/oj/mimic.rb, which starts with require 'bigdecimal'. On
#   Ruby 3.4 that raises LoadError. 3.16.2 is the first release that
#   declares bigdecimal. Up to 3.16.4, oj also requires ostruct without
#   declaring it, but inside begin/rescue Exception, so Ruby 3.4 and 4.0
#   only warn and oj still loads. That warning alone does not justify
#   excluding those releases.
# - json_schemer 2.0.0 to 2.1.1 require base64 and bigdecimal
#   (lib/json_schemer.rb) and declare neither. 2.2.0 declares both.

## oj's requirement excludes the releases that load bigdecimal without declaring it
oj = @gemspec.runtime_dependencies.find { |dep| dep.name == 'oj' }
%w[3.16.1 3.16.2].map { |version| oj.requirement.satisfied_by?(Gem::Version.new(version)) }
#=> [false, true]

## json_schemer's requirement excludes the releases that load base64 and bigdecimal without declaring them
json_schemer = @gemspec.runtime_dependencies.find { |dep| dep.name == 'json_schemer' }
%w[2.0.0 2.1.1 2.2.0].map { |version| json_schemer.requirement.satisfied_by?(Gem::Version.new(version)) }
#=> [false, false, true]
