# frozen_string_literal: true

require_relative 'lib/perchfall/version'

Gem::Specification.new do |spec|
  spec.name          = 'perchfall'
  spec.version       = Perchfall::VERSION
  spec.authors       = ['Jim Remsik']
  spec.email         = ['jim@beflagrant.com']

  spec.summary       = 'Synthetic browser monitoring via Playwright'
  spec.description   = <<~DESC
    Run headless browser checks against a URL using Playwright and receive a
    structured, immutable Ruby report object — framework-agnostic, no persistence.
  DESC
  spec.homepage      = 'https://github.com/beflagrant/perchfall'
  spec.license       = 'MIT'
  spec.metadata      = {
    'source_code_uri' => 'https://github.com/beflagrant/perchfall',
    'changelog_uri' => 'https://github.com/beflagrant/perchfall/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/beflagrant/perchfall/issues',
    'rubygems_mfa_required' => 'true'
  }

  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir[
    'lib/**/*',
    'playwright/**/*',
    'README.md',
    'CHANGELOG.md',
    'LICENSE.txt',
    'perchfall.gemspec'
  ].reject { |f| File.directory?(f) }

  spec.require_paths = ['lib']

  spec.post_install_message = <<~MSG
    perchfall requires Node.js and Playwright to run browser checks.
    After installing this gem, run:

      npm install playwright
      npx playwright install chromium
  MSG

  # json is in stdlib but declared explicitly so bundler resolves it correctly
  spec.add_dependency 'json', '>= 2.0'

  spec.add_development_dependency 'rspec',      '~> 3.13'
  spec.add_development_dependency 'rubocop',    '~> 1.70'
  spec.add_development_dependency 'simplecov',  '~> 0.22'
end
