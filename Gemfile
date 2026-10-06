source "https://rubygems.org"

gemspec

gem "rake", "~> 13.0"
gem "rspec", "~> 3.13"
# The ISC YAML bridge (lib/interscript/isc/yaml_bridge.rb) hard-requires
# lutaml/model; the round-trip specs exercise it. Dev-only here — the
# gemspec does not declare it (owner decision; the autoload fails
# without it).
gem "lutaml-model"

if File.exist?("../maps")
  gem "interscript-maps", path: "../maps"
else
  gem "interscript-maps"
end

# The neural layer (Interscript::ML) - optional at runtime, loaded for specs
group :ml do
  gem "rubyzip"
  gem "onnxruntime"
end

gem "regexp_parser"

unless ENV["SKIP_JS"]
  group :jsexec do
    gem "mini_racer"
  end
end

unless ENV["SKIP_PYTHON"]
  group :pyexec do
    gem "pycall"
  end
end

group :rababa do
  gem "rababa", "~> 0.1.1"
end

gem "pry"
gem "iso-639-data"
gem "iso-15924"

gem "simplecov", require: false, group: :test
gem "standard", group: :development, require: false
