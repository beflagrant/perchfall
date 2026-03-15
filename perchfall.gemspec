# frozen_string_literal: true

require_relative "lib/perchfall/version"

Gem::Specification.new do |spec|
  spec.name          = "perchfall"
  spec.version       = Perchfall::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["you@example.com"]

  spec.summary       = "Synthetic browser monitoring via Playwright"
  spec.description   = <<~DESC
    Run headless browser checks against a URL using Playwright and receive a
    structured, immutable Ruby report object — framework-agnostic, no persistence.
  DESC
  spec.homepage      = "https://github.com/yourorg/perchfall"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir[
    "lib/**/*",
    "playwright/**/*",
    "bin/*",
    "README.md",
    "LICENSE.txt",
    "perchfall.gemspec"
  ].reject { |f| File.directory?(f) }

  spec.bindir        = "bin"
  spec.executables   = ["console"]
  spec.require_paths = ["lib"]

  # json is in stdlib but declared explicitly so bundler resolves it correctly
  spec.add_dependency "json", ">= 2.0"

  spec.add_development_dependency "rspec",    "~> 3.13"
  spec.add_development_dependency "rubocop",  "~> 1.70"
end
