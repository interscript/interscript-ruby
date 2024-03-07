source "https://rubygems.org"

# Specify your gem's dependencies in interscript.gemspec
gemspec

gem "rake", "~> 12.0"
gem "rspec", "~> 3.0"

gem "interscript-maps", path: "../maps"

unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.7")
  group :secryst do
    if File.exist? "../../secryst"
      gem "secryst", path: "../../secryst"
    else
      gem "secryst"
    end
  end
end

gem 'regexp_parser'

unless ENV["SKIP_JS"]
  group :jsexec do
    gem 'mini_racer'
  end
end

unless ENV["SKIP_PYTHON"]
  group :pyexec do
    gem 'pycall'
  end
end

group :rababa do
  gem 'rababa', "~> 0.1.1"
end

gem 'pry'

gem 'iso-639-data'
gem 'iso-15924'

gem 'simplecov', require: false, group: :test
