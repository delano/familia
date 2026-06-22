# frozen_string_literal: true

# Bundler's standard gem tasks: build / install / release (and release:*).
#
# The release-gem.yml workflow publishes via the `rubygems/release-gem` action,
# which runs `bundle exec rake release`. That task only exists when this file
# requires bundler/gem_tasks; without it the release job fails with
# "Don't know how to build task 'release'". `rake` lives in the (non-optional)
# :development, :test Gemfile group, so the release job's default `bundle install`
# already provides it -- no BUNDLE_WITH opt-in is needed here.
require 'bundler/gem_tasks'

# Run the Tryouts test suite with a guaranteed UTF-8 locale.
#
# The suite's source and specs are UTF-8. The tryouts runner reads each test file
# with File.read, which honours Encoding.default_external; when the caller's
# locale is unset that defaults to US-ASCII and the run aborts on non-ASCII source
# ("invalid byte sequence in US-ASCII"), with encoding-sensitive specs failing
# spuriously. Running the suite in a child process with a UTF-8 locale makes it
# work regardless of the caller's environment. A caller that already has a UTF-8
# locale (CI, most shells) keeps it -- the defaults below only fill in when unset.
desc 'Run the Tryouts test suite (ensures a UTF-8 locale)'
task :test do
  ENV['LANG'] ||= 'C.UTF-8'
  ENV['LC_ALL'] ||= 'C.UTF-8'
  sh 'bundle exec try -vf'
end

task default: :test
