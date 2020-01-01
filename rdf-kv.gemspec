# -*- mode: enh-ruby -*-
require_relative 'lib/rdf/kv/version'

Gem::Specification.new do |spec|
  spec.name          = 'rdf-kv'
  spec.version       = RDF::KV::VERSION
  spec.authors       = ['Dorian Taylor']
  spec.email         = ['code@doriantaylor.com']
  spec.license       = 'Apache-2.0'
  spec.homepage      = 'https://github.com/doriantaylor/rb-rdf-kv'
  spec.summary       = 'Ruby implementation of the RDF-KV protocol'
  spec.description   = <<-DESC
This module implements https://doriantaylor.com/rdf-kv, taking
key-value input (e.g. from a Web form) and converting it into an
RDF::Changeset.
  DESC

  spec.metadata['homepage_uri'] = spec.homepage

  # Specify which files should be added to the gem when it is
  # released. The `git ls-files -z` loads the files in the RubyGem
  # that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      f.match(%r{^(test|spec|features)/})
    end
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = Gem::Requirement.new('>= 2.3.0')
  # dev/test dependencies
  spec.add_development_dependency 'bundler', '~> 2'

  # stuff we use
  spec.add_runtime_dependency 'rdf', '>= 3.0.12'
end
