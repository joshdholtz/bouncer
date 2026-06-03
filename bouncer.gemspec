require_relative "lib/bouncer/version"

Gem::Specification.new do |spec|
  spec.name          = "bouncer"
  spec.version       = Bouncer::VERSION
  spec.authors       = ["Josh Holtz"]
  spec.email         = ["me@joshholtz.com"]
  spec.summary       = "Config-driven Discord bot for conference attendee verification"
  spec.description   = "bouncer reads a YAML config file to register slash commands, verify tickets against a provider (like Tito), and assign Discord roles. Add a new year by adding a YAML block — no code changes needed."
  spec.homepage      = "https://github.com/joshdholtz/bouncer"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*", "LICENSE", "README.md", "bouncer.example.yml"]
  spec.require_paths = ["lib"]

  spec.add_dependency "discordrb", "~> 3.5"
  spec.add_dependency "rest-client", "~> 2.1"
  spec.add_dependency "dotenv", "~> 3.0"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
