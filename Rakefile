require "bundler/gem_tasks"
require 'opal'

class OpalBuilder < Opal::Builder
  attr_accessor :build_source_map
  def to_s
      if @build_source_map
          super + "\n" + source_map.to_data_uri_comment
      else
          super
      end
  end
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

desc "Remove javascript files"
task :clear do
    Dir.glob('vendor/assets/javascripts/*').each { |f| File.delete(f) }
end

desc "convert map yaml files into .js files as json"
task :maps do
    sh "cd ./maps && erb -r ./maps.rb   maps.js.erb > ../vendor/assets/javascripts/maps.js"
end

desc "Build javascript version of interscript gem"
task :build do
    Opal.append_path 'lib'
    Dir['lib/*/'].each do | path |
        Opal.append_path path.untaint
    end 

    builder = OpalBuilder.new
    builder.build_source_map = true
    ['opal', 'rambling-trie-opal'].each {|gem| builder.use_gem gem}    
    builder.build('interscript.rb')

    File.open("dist/interscript.js", "w+") do |out|
        out << builder.to_s
    end
end

desc "All in one"
task :all => [:clear] do
    Rake::Task["maps"].execute
    Rake::Task["build"].execute
end