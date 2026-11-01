# try/support/helpers/fresh_ruby.rb
#
# frozen_string_literal: true

require 'open3'
require 'rbconfig'

# Runs Ruby code in a new process and returns its standard output as
# stripped lines. Use it when a testcase needs a process in which nothing
# has been required yet, for example to check what require 'familia' loads.
# The tryouts share one process, so they cannot answer that question.
#
# The child inherits this process's environment, including Bundler's
# RUBYOPT, so it resolves gems from the same bundle. Its load path starts
# with the load_path entries, then this checkout's lib/.
#
# Only standard output is returned. Standard error carries output the
# testcase does not control, such as Ruby warnings under -w or git's
# complaint when Bundler evaluates familia.gemspec outside a git checkout,
# so it appears only in the error raised when the child fails.
def run_fresh_ruby(code, load_path: [])
  lib_dir = File.expand_path('../../../lib', __dir__)
  includes = [*load_path, lib_dir].flat_map { |dir| ['-I', dir] }
  out, err, status = Open3.capture3(RbConfig.ruby, *includes, '-e', code)
  raise "fresh ruby exited #{status.exitstatus}:\n#{err}#{out}" unless status.success?

  out.lines.map(&:strip)
end
