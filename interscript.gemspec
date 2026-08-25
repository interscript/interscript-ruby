require_relative "lib/interscript/version"

Gem::Specification.new do |spec|
  spec.name = "interscript"
  spec.version = Interscript::VERSION
  spec.summary = "Interoperable script conversion systems"
  spec.description = "Interoperable script conversion systems."
  spec.authors = ["Ribose Inc."]
  spec.email = ["open.source@ribose.com"]

  spec.homepage = "https://www.interscript.com"
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/interscript/interscript-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/interscript/interscript-ruby/releases"
  spec.metadata["bug_tracker_uri"] = "https://github.com/interscript/interscript-ruby/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*",
      "exe/**/*",
      "docs/**/*",
      "README*",
      "LICENSE*",
      "*.gemspec"
    ].select { |f| File.file?(f) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "thor"
  spec.add_dependency "interscript-maps", "~> #{Interscript::VERSION.split(".")[0, 2].join(".")}.0a"
  spec.add_dependency "text"
  spec.add_dependency "parslet", "~> 2.0"
end
