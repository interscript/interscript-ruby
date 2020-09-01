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
  require "yaml"
  require_relative "lib/interscript/opal_map_translate"

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

desc "All in one"
task all: [:clean] do
  Rake::Task["js"].execute
end
