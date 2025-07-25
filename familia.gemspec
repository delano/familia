# frozen_string_literal: true

require_relative 'lib/familia/version'

Gem::Specification.new do |spec|
  spec.name        = 'familia'
  spec.version     = Familia::VERSION
  spec.summary     = 'An ORM for Redis in Ruby.'
  spec.description = "Familia: #{spec.summary}. Organize and store ruby objects in Redis"
  spec.authors     = ['Delano Mandelbaum']
  spec.email       = 'gems@solutious.com'
  spec.homepage    = 'https://github.com/delano/familia'
  spec.license     = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = Gem::Requirement.new('>= 3.4')

  spec.add_dependency 'benchmark'
  spec.add_dependency 'connection_pool'
  spec.add_dependency 'csv'
  spec.add_dependency 'logger'
  spec.add_dependency 'redis', '>= 4.8.1', '< 6.0'
  spec.add_dependency 'stringio', '~> 3.1.1'
  spec.add_dependency 'uri-redis', '~> 1.3'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
