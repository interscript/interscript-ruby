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

desc "Correct file names in 'maps' directory to ensure to be uppercase for 3rd and 4rd"
task :rename do
  require 'yaml'

  root_path = File.expand_path File.dirname(__FILE__)
  changed = []
  edited = []
  Dir['maps/*.yaml'].each do |yaml_file|
    org_name = File.basename(yaml_file, ".yaml")

    capitalize_filename = proc do |org_name|
      terms = org_name.split("-")
      terms[2].capitalize!
      terms[3].capitalize!
      terms.join("-")
    end

    new_name = capitalize_filename.(org_name)
    new_name_full = root_path + '/maps/' + new_name + ".yaml"

    if org_name != new_name
      File.rename(yaml_file, new_name_full)
      changed << new_name
    end

    org_file = File.read(new_name_full)
    yaml = YAML.load(org_file)
    if org_inherit = yaml.dig("map", "inherit")
      new_inherit = case org_inherit
      when Array
        org_inherit.map(&capitalize_filename)
      when String
        capitalize_filename.(org_inherit)
      else
        raise "#{org_inherit} has a type different from String/Array"
      end

      if new_inherit != org_inherit
        # [4..-2] removes the initial magic signature from YAML and a new line from the end
        new_file = org_file.gsub(YAML.dump(org_inherit)[4..-2], YAML.dump(new_inherit)[4..-2])

        if org_file != new_file
          File.write(new_name_full, new_file)
          edited << new_name
        else
          raise "Couldn't fix #{new_name}"
        end
      end
    end
  end

  puts "Total Scanned: #{Dir['maps/*.yaml'].size} files"
  puts "Renamed Count: #{changed.size} "
  puts "Fixed Count: #{edited.size} "
  changed.each { |new_name| puts new_name }
end

desc "All in one"
task all: [:clean, :rename] do
  Rake::Task["js"].execute
  Rake::Task["js_maps"].execute
end
