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

desc "Build javascript version of interscript gem"
task :javascript do
    require 'opal/builder'
    require 'opal/builder_processors'
    require "erb"
    require "json"
    require "yaml"    

    builder = Opal::Builder.new

    builder.append_paths 'opal'

    ['rambling-trie-opal'].each {|gem| builder.use_gem gem}
    builder.build('interscript.rb')
    
    File.open("vendor/assets/javascripts/interscript.js", "w+") do |out|
        out << builder.to_s
    end
end

desc "All in one"
task :all => [:clean] do
    Rake::Task["javascript"].execute
end