Gem::Specification.new do |s|
  s.name        = "familia"
  s.version     = "0.8.0-RC1"
  s.summary     = "Organize and store ruby objects in Redis"
  s.description = "Organize and store ruby objects in Redis"
  s.authors     = ["Delano Mandelbaum"]
  s.email       = "delano@solutious.com"
  s.homepage    = "http://github.com/delano/familia"
  s.license     = "MIT"

  s.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  s.bindir        = "exe"
  s.executables   = s.files.grep(%r{^exe/}) { |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  s.add_dependency "redis", ">= 2.1.0"
  s.add_dependency "uri-redis", ">= 0.4.2"
  s.add_dependency "gibbler", ">= 0.10.0.pre.RC1"
  s.add_dependency "storable", ">= 0.10.pre.RC2"
  s.add_dependency "multi_json", ">= 0.0.5"
end
