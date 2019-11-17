
# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'transcriptionkit/version'
require 'rake'

Gem::Specification.new do |spec|
  spec.name          = "transcriptionkit"
  spec.version       = TranscriptionKit::VERSION
  spec.required_rubygems_version = Gem::Requirement.new('>= 0') if s.respond_to? :required_rubygems_version=
  spec.summary       = %q{ Gem used for calculating translite.}
  spec.description   = %q{Gem used for calculating translit.}
  s.date = %q{2019-11-17}
  spec.homepage      = ""
  spec.license       = "MIT"
  spec.files = FileList['{bin,lib,test}/**/*', 'README.markdown'].to_a
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  s.bindir = 'bin'
  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
