Gem::Specification.new do |spec|
  spec.name        = "familia"
  spec.version     = "0.10.2"
  spec.summary     = "An ORM for Redis in Ruby."
  spec.description = "Familia: #{spec.summary}. Organize and store ruby objects in Redis"
  spec.authors     = ["Delano Mandelbaum"]
  spec.email       = "gems@solutious.com"
  spec.homepage    = "https://github.com/delano/familia"
  spec.license     = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.8")

  spec.add_dependency 'redis', '>= 4.8.1', '< 6.0'
  spec.add_dependency 'uri-redis', '~> 1.3'
  spec.add_dependency 'gibbler', '~> 1.0.0'
  spec.add_dependency 'storable', '~> 0.10.0'
  spec.add_dependency 'multi_json', '~> 1.15'

  # byebug only works with MRI
  if RUBY_ENGINE == "ruby"
    spec.add_development_dependency 'byebug', '~> 11.0'
  end
end
