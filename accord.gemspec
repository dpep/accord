require_relative "lib/accord/version"

Gem::Specification.new do |s|
  s.authors     = ["Daniel Pepper"]
  s.description = "A declarative DSL for defining input schemas that parse, validate, and document API boundaries."
  s.files       = `git ls-files * ':!:spec'`.split("\n")
  s.homepage    = "https://github.com/dpep/accord"
  s.license     = "MIT"
  s.name        = "accord"
  s.summary     = "Executable API contracts for Ruby"
  s.version     = Accord::VERSION

  s.required_ruby_version = ">= 3.3"

  s.add_dependency "bigdecimal"

  s.add_development_dependency "activesupport"
  s.add_development_dependency "debug"
  s.add_development_dependency "money"
  s.add_development_dependency "openapi3_parser"
  s.add_development_dependency "rspec"
  s.add_development_dependency "simplecov"
  s.add_development_dependency "tapioca"
end
