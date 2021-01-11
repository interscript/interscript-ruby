
# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'interscript/version'

Gem::Specification.new do |spec|
  spec.name          = "interscript"
  spec.version       = Interscript::VERSION
  spec.required_rubygems_version = Gem::Requirement.new('>= 2.4.0') if spec.respond_to? :required_rubygems_version=
  spec.summary       = %q{Interoperable script conversion systems}
  spec.description   = %q{Interoperable script conversion systems}
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.date = %q{2019-11-17}
  spec.homepage      = "https://www.interscript.com"
  spec.license       = "MIT"
  spec.files = Dir.glob("{lib,exe,spec,maps}/**/*", File::FNM_DOTMATCH)
  spec.files += ['README.adoc', 'aliases.json']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]
  spec.bindir = "bin"

  spec.add_dependency "thor"

  spec.add_development_dependency "pry"
  spec.add_development_dependency "pycall"
  spec.add_development_dependency "rambling-trie"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"

  spec.add_development_dependency 'rambling-trie-opal'
  spec.add_development_dependency 'opal', '~> 1.0.3'
  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-rake'
  spec.add_development_dependency "closure-compiler" #, github: "hmdne/closure-compiler"

end
