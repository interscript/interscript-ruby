require "bundler/gem_tasks"

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

desc "Remove javascript files"
task :clean do
  Dir.glob('vendor/assets/javascripts/*').each { |f| File.delete(f) }
end

desc "Build Interscript JavaScript"
task :js do
  puts "creating javascript version..."
  require 'opal/builder'
  require 'opal/builder_processors'
  require "erb"
  require "json"

  builder = Opal::Builder.new

  # builder.preload << "lib"
  builder.append_paths "lib"

  %w(rambling-trie-opal).each do |gem|
    builder.use_gem gem
  end

  builder.build('interscript-opal.rb')

  File.open("vendor/assets/javascripts/interscript.js", "w+") do |out|
    out << builder.to_s
  end
end

desc "Build Interscript maps for use with Opal"
task :js_maps do
  require "yaml"
  require "fileutils"
  require_relative "lib/interscript/opal_map_translate"

  FileUtils.mkdir_p "vendor/assets/maps"

  Dir['maps/*.yaml'].each do |yaml_file|
    f = File.read(yaml_file)
    f = YAML.load(f)
    f = JSON.dump(f)
    f = Interscript::OpalMapTranslate.translate_regexp(f)
    File.write("vendor/assets/maps/#{File.basename yaml_file, ".yaml"}.json", f)
  end
end

desc "All in one"
task all: [:clean] do
  Rake::Task["js"].execute
  Rake::Task["js_maps"].execute
end
