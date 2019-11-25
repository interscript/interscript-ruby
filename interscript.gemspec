
# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'interscript/version'
require 'rake'

Gem::Specification.new do |spec|
  spec.name          = "interscript"
  spec.version       = Interscript::VERSION
  spec.required_rubygems_version = Gem::Requirement.new('>= 0') if spec.respond_to? :required_rubygems_version=
  spec.summary       = %q{Interoperable script conversion systems}
  spec.description   = %q{Interoperable script conversion systems}
  spec.authors = ['project_contibutors']
  spec.date = %q{2019-11-17}
  spec.homepage      = ""
  spec.license       = "MIT"
  spec.files = FileList['{bin,lib,spec,maps}/**/*', 'README.adoc'].to_a
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.bindir = 'bin'

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "debase"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "ruby-debug-ide"
end
