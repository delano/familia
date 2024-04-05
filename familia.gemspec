Gem::Specification.new do |s|
  s.name        = "familia"
  s.version     = "0.9.2"
  s.summary     = "Organize and store ruby objects in Redis"
  s.description = "Familia: #{s.summary}"
  s.authors     = ["Delano Mandelbaum"]
  s.email       = "delano@solutious.com"
  s.homepage    = "https://github.com/delano/familia"
  s.license     = "MIT"

  s.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  s.bindir        = "exe"
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.required_ruby_version = Gem::Requirement.new(">= 2.6.8")

  s.add_dependency "redis", ">= 4.8", "< 7"
  s.add_dependency "uri-redis", ">= 1.0.0"
  s.add_dependency "gibbler", "~> 1.0.0"
  s.add_dependency "storable", "~> 0.10.0"
  s.add_dependency "multi_json", "~> 1.15"
end
