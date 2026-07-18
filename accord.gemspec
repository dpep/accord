# frozen_string_literal: true

require_relative "lib/accord/version"

Gem::Specification.new do |spec|
  spec.name = "accord"
  spec.version = Accord::VERSION
  spec.authors = ["Daniel Pepper"]
  spec.email = ["pepper.daniel@gmail.com"]

  spec.summary = "Executable API contracts for Ruby."
  spec.description = "A declarative DSL for defining input schemas that parse, " \
                     "validate, and document API boundaries."
  spec.homepage = "https://github.com/dpep/accord"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE*"]
  spec.require_paths = ["lib"]

  # bigdecimal and date are used for Currency and Date types.
  spec.add_dependency "bigdecimal"

  spec.add_development_dependency "activesupport"
  spec.add_development_dependency "rspec", "~> 3.0"
end
