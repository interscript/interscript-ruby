
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
  spec.files = FileList['{bin,lib,test}/**/*', 'README.adoc'].to_a
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.bindir = 'bin'
  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
