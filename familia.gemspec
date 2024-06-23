Gem::Specification.new do |s|
  s.name        = "familia"
  s.version     = "0.10.1"
  s.summary     = "Organize and store ruby objects in Redis"
  s.description = "Familia: #{s.summary}"
  s.authors     = ["Delano Mandelbaum"]
  s.email       = "gems@solutious.com"
  s.homepage    = "https://github.com/delano/familia"
  s.license     = "MIT"

  s.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  s.bindir        = "exe"
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.required_ruby_version = Gem::Requirement.new(">= 2.7.8")

  # byebug only works with MRI
  if RUBY_ENGINE == "ruby"
    s.add_development_dependency 'byebug', '~> 11.0'
  end
end
