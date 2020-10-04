source 'https://rubygems.org'

gemspec

if File.directory? __dir__+"/../opal-onigmo"
  gem "opal-onigmo", path: __dir__+"/../opal-onigmo"
else
  gem "opal-onigmo"
end

if File.directory? __dir__+"/../opal-webassembly"
  gem "opal-webassembly", path: __dir__+"/../opal-webassembly"
else
  gem "opal-webassembly"
end
