# frozen_string_literal: true

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = "uchip"
  s.version     = "1.0.0"
  s.summary     = "Gem for controlling MCP2221a"
  s.description = "This is a gem for controlling the MCP2221a chip over USB"

  s.license = "MIT"

  s.files = `git ls-files`.split("\n")
  s.require_path = 'lib'

  s.author   = "Aaron Patterson"
  s.email    = "tenderlove@ruby-lang.org"
  s.homepage = "https://github.com/tenderlove/uchip"

  s.files = ["README.md"]

  s.add_dependency "myhidapi", "~> 1.0"
end
